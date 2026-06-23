import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import '../core/config.dart';
import '../core/languages.dart';
import 'app_logger.dart';
import 'model_manager.dart';

final _L = AppLogger.instance;

const _channel = MethodChannel('com.pia.translate/sentencepiece');

// ── SentencePiece — 메인 isolate 전용 (MethodChannel) ─────────────────
Future<List<int>> _spEncode(String spModelPath, String text) async {
  _L.log('SP', '인코딩 입력: "${text.length > 40 ? text.substring(0, 40) + "…" : text}"');
  final ids = await _channel.invokeMethod<List<dynamic>>(
    'encode', {'modelPath': spModelPath, 'text': text});
  final result = ids?.cast<int>() ?? [];
  _L.log('SP', '인코딩 결과: ${result.length}개 토큰 ${result.take(10).toList()}');
  return result;
}

Future<String> _spDecode(String spModelPath, List<int> ids) async {
  _L.log('SP', '디코딩 입력: ${ids.length}개 토큰 ${ids.take(10).toList()}');
  final text = await _channel.invokeMethod<String>(
    'decode', {'modelPath': spModelPath, 'ids': ids});
  final result = text ?? '';
  _L.log('SP', '디코딩 결과: "${result.length > 60 ? result.substring(0, 60) + "…" : result}"');
  return result;
}

// ── 영구 ONNX Isolate ──────────────────────────────────────────────────
// compute()는 호출마다 새 isolate를 생성해 모델을 디스크에서 재로드(매번 5~15초).
// 영구 isolate는 OrtSession을 메모리에 캐시 → 첫 번역 후 즉시 응답.
Future<SendPort>? _onnxIsolateFuture;

Future<SendPort> _ensureOnnxIsolate() =>
    _onnxIsolateFuture ??= _spawnOnnxIsolate();

Future<SendPort> _spawnOnnxIsolate() async {
  final boot = ReceivePort();
  await Isolate.spawn(_onnxIsolateMain, boot.sendPort);
  final sendPort = await boot.first as SendPort;
  boot.close();
  return sendPort;
}

// ── Isolate 메인 — 세션 캐시 보유 ────────────────────────────────────
void _onnxIsolateMain(SendPort mainPort) {
  final port = ReceivePort();
  mainPort.send(port.sendPort); // 핸드셰이크

  final Map<String, OrtSession> cache = {};

  OrtSession _get(String path) => cache.putIfAbsent(path, () {
    final opts = OrtSessionOptions()
      ..setIntraOpNumThreads(4)
      ..setInterOpNumThreads(1);
    return OrtSession.fromFile(File(path), opts);
  });

  port.listen((msg) {
    if (msg is! Map) return;
    final reply = msg['replyPort'] as SendPort;
    final type  = (msg['type'] as String?) ?? 'translate';

    try {
      switch (type) {
        case 'preload':
          _get(msg['encoderPath'] as String);
          _get(msg['decoderPath'] as String);
          reply.send({'ok': true});

        case 'evict':
          final key = msg['path'] as String;
          cache[key]?.release();
          cache.remove(key);
          reply.send({'ok': true});

        default: // translate
          final isolateLogs = <String>[];
          final tokens = _onnxInfer(
            encoder:    _get(msg['encoderPath'] as String),
            decoder:    _get(msg['decoderPath'] as String),
            configPath: msg['configPath'] as String,
            inputIds:   List<int>.from(msg['inputIds'] as List),
            maxLen:     msg['maxLen'] as int,
            logs:       isolateLogs,
          );
          reply.send({'ok': true, 'tokens': tokens, 'log': isolateLogs});
      }
    } catch (e) {
      reply.send({'ok': false, 'error': e.toString()});
    }
  });
}

// ── ONNX 추론 — 세션 캐시 사용 (해제 안 함) ───────────────────────────
List<int> _onnxInfer({
  required OrtSession encoder,
  required OrtSession decoder,
  required String configPath,
  required List<int> inputIds,
  required int maxLen,
  List<String>? logs,
}) {
  // config.json에서 BOS/EOS 결정
  int eosId = 0;
  int bosId = 65001;
  bool cfgFound = false;
  String cfgSrc = 'default(65001)';
  final cfg = File(configPath);
  if (cfg.existsSync()) {
    try {
      final map = jsonDecode(cfg.readAsStringSync()) as Map<String, dynamic>;
      cfgFound = true;
      eosId = (map['eos_token_id'] as num?)?.toInt() ?? 0;
      final sid = (map['decoder_start_token_id'] as num?)?.toInt();
      final pid = (map['pad_token_id']            as num?)?.toInt();
      final vid = (map['vocab_size']              as num?)?.toInt();
      logs?.add('config: eos=$eosId start=$sid pad=$pid vocab=$vid');
      if (sid != null && sid != eosId) {
        bosId = sid; cfgSrc = 'decoder_start_token_id';
      } else if (pid != null && pid != eosId) {
        bosId = pid; cfgSrc = 'pad_token_id';
      } else if (vid != null && vid - 1 != eosId) {
        bosId = vid - 1; cfgSrc = 'vocab_size-1';
      }
    } catch (e) { logs?.add('config 파싱 오류: $e'); }
  } else {
    logs?.add('config.json 없음 → 기본값 사용');
  }
  logs?.add('bosId=$bosId (출처:$cfgSrc) eosId=$eosId cfgFound=$cfgFound');

  // 인코더 실행
  final inTensor   = OrtValueTensor.createTensorWithDataList(Int64List.fromList(inputIds), [1, inputIds.length]);
  final maskTensor = OrtValueTensor.createTensorWithDataList(Int64List.fromList(List.filled(inputIds.length, 1)), [1, inputIds.length]);

  logs?.add('인코더 실행: 입력 ${inputIds.length}토큰');
  final encOut    = encoder.run(OrtRunOptions(), {'input_ids': inTensor, 'attention_mask': maskTensor});
  final hiddenRaw = encOut[0]?.value as List;
  final seqLen    = (hiddenRaw[0] as List).length;
  final hidSize   = ((hiddenRaw[0] as List)[0] as List).length;
  logs?.add('인코더 완료: seqLen=$seqLen hidSize=$hidSize');

  final hidden = Float32List(seqLen * hidSize);
  for (int i = 0; i < seqLen; i++) {
    final row = (hiddenRaw[0] as List)[i] as List;
    for (int j = 0; j < hidSize; j++) hidden[i * hidSize + j] = (row[j] as num).toDouble();
  }
  inTensor.release(); maskTensor.release();
  for (final v in encOut) { v?.release(); }

  // 디코더 greedy — eHid/eAttn은 매 스텝 동일하므로 루프 밖에서 한 번만 생성
  final eHid  = OrtValueTensor.createTensorWithDataList(hidden, [1, seqLen, hidSize]);
  final eAttn = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(List.filled(seqLen, 1)), [1, seqLen]);
  final runOpts = OrtRunOptions();
  logs?.add('디코더 greedy 시작: maxLen=$maxLen');

  final out = [bosId];
  int finalStep = 0;
  try {
    for (int step = 0; step < maxLen; step++) {
      finalStep = step;
      final dIn    = OrtValueTensor.createTensorWithDataList(Int64List.fromList(out), [1, out.length]);
      final decOut = decoder.run(runOpts, {
        'input_ids':               dIn,
        'encoder_hidden_states':   eHid,
        'encoder_attention_mask':  eAttn,
      });
      final lastLogits = ((decOut[0]?.value as List)[0] as List).last as List;

      int nextToken = 0; double maxVal = double.negativeInfinity;
      for (int i = 0; i < lastLogits.length; i++) {
        final v = (lastLogits[i] as num).toDouble();
        if (v > maxVal) { maxVal = v; nextToken = i; }
      }
      dIn.release();
      for (final v in decOut) { v?.release(); }

      if (nextToken == eosId) break;
      out.add(nextToken);
    }
  } finally {
    eHid.release();
    eAttn.release();
  }
  // 세션은 해제 안 함 — 캐시에서 재사용

  final generated = out.sublist(1);
  logs?.add('디코더 완료: ${finalStep+1}스텝 → ${generated.length}토큰 생성');
  logs?.add('출력 토큰ID(앞20): ${generated.take(20).toList()}');
  // 반복 패턴 감지
  if (generated.length > 4) {
    final unique = generated.toSet().length;
    logs?.add('유니크 토큰: $unique / 전체: ${generated.length} (반복률: ${((1 - unique / generated.length) * 100).round()}%)');
  }
  return generated;
}

// ── 공개 API ──────────────────────────────────────────────────────────

/// 언어쌍 세션 사전 로드 — 다운로드 완료 후 또는 언어 변경 시 호출
/// 첫 번역 대기 없이 즉시 응답 가능하도록 미리 warm-up
Future<void> preloadSessions(String modelDir) async {
  final port  = await _ensureOnnxIsolate();
  final reply = ReceivePort();
  port.send({
    'type':        'preload',
    'encoderPath': p.join(modelDir, 'encoder_model.onnx'),
    'decoderPath': p.join(modelDir, 'decoder_model.onnx'),
    'replyPort':   reply.sendPort,
  });
  await reply.first;
  reply.close();
}

Future<String> _translateWithModel({
  required String modelDir,
  required String inputText,
}) async {
  final srcSpm = p.join(modelDir, 'tokenizer', 'source.spm');
  final tgtSpm = p.join(modelDir, 'tokenizer', 'target.spm');

  final inputIds = await _spEncode(srcSpm, inputText);
  if (inputIds.isEmpty) return inputText;

  final port  = await _ensureOnnxIsolate();
  final reply = ReceivePort();
  port.send({
    'type':        'translate',
    'encoderPath': p.join(modelDir, 'encoder_model.onnx'),
    'decoderPath': p.join(modelDir, 'decoder_model.onnx'),
    'configPath':  p.join(modelDir, 'config.json'),
    'inputIds':    inputIds,
    'maxLen':      AppConfig.maxOutputLength,
    'replyPort':   reply.sendPort,
  });

  final res = await reply.first as Map;
  reply.close();

  // isolate에서 보낸 로그를 메인 isolate의 AppLogger에 기록
  for (final l in (res['log'] as List? ?? [])) {
    _L.log('ONNX', l.toString());
  }

  if (res['ok'] != true) {
    _L.log('ERR', 'ONNX 오류: ${res['error']}');
    throw Exception(res['error']);
  }
  final tokens = List<int>.from(res['tokens'] as List);
  if (tokens.isEmpty) {
    _L.log('WARN', '출력 토큰 없음 → 원문 반환');
    return inputText;
  }

  return _spDecode(tgtSpm, tokens);
}

const _romanceModels = {'en_fr', 'en_es', 'en_it', 'en_pt', 'en_ro'};
String _modelLangPrefix(String modelName, String dstLang) =>
    _romanceModels.contains(modelName) ? '>>$dstLang<< ' : '';

Future<String> translate({
  required String text,
  required String srcLang,
  required String dstLang,
}) async {
  if (srcLang == dstLang || text.trim().isEmpty) return text;
  final route = translationRoute(srcLang, dstLang);
  if (route.isEmpty) return text;

  _L.log('TR', '번역 시작: $srcLang→$dstLang 경로=$route 입력="${text.length > 30 ? text.substring(0, 30) + "…" : text}"');
  final mm = ModelManager.instance;
  String current = text;
  for (final modelName in route) {
    if (!await mm.isDownloaded(modelName)) {
      throw Exception('번역 모델 미다운로드: $modelName');
    }
    final dir   = await mm.modelPath(modelName);
    final input = _modelLangPrefix(modelName, dstLang) + current;
    _L.log('TR', '모델[$modelName] 실행, 입력="${input.length > 30 ? input.substring(0, 30) + "…" : input}"');
    current = await _translateWithModel(modelDir: dir, inputText: input);
    _L.log('TR', '모델[$modelName] 완료 → "${current.length > 40 ? current.substring(0, 40) + "…" : current}"');
  }
  _L.log('TR', '최종 결과: "$current"');
  return current;
}

/// 앱 종료 또는 메모리 해제 시 호출
void releaseAllSessions() {
  _onnxIsolateFuture = null;
}
