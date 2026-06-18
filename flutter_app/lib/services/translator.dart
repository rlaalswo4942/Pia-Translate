import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import '../core/config.dart';
import '../core/languages.dart';
import 'model_manager.dart';

/// Android 네이티브 SentencePiece JNI 채널
const _channel = MethodChannel('com.pia.translate/sentencepiece');

/// 로드된 ONNX 세션 캐시 (경로 → 세션)
final _sessionCache = <String, OrtSession>{};
bool _ortReady = false;

void _ensureOrt() {
  if (_ortReady) return;
  try {
    OrtEnv.instance.init();
    _ortReady = true;
  } catch (e) {
    debugPrint('OrtEnv.init failed: $e');
  }
}

OrtSession _loadSession(String modelPath) {
  _ensureOrt();
  return _sessionCache.putIfAbsent(modelPath, () {
    final opts = OrtSessionOptions();
    return OrtSession.fromFile(File(modelPath), opts);
  });
}

/// SentencePiece 인코딩 (Kotlin JNI 경유)
Future<List<int>> _spEncode(String spModelPath, String text) async {
  final ids = await _channel.invokeMethod<List<dynamic>>(
    'encode',
    {'modelPath': spModelPath, 'text': text},
  );
  return ids?.cast<int>() ?? [];
}

/// SentencePiece 디코딩 (Kotlin JNI 경유)
Future<String> _spDecode(String spModelPath, List<int> ids) async {
  final text = await _channel.invokeMethod<String>(
    'decode',
    {'modelPath': spModelPath, 'ids': ids},
  );
  return text ?? '';
}

/// 단일 모델로 번역 (ONNX seq2seq, greedy decoding)
Future<String> _translateWithModel({
  required String modelDir,
  required String inputText,
}) async {
  final encoderPath = p.join(modelDir, 'encoder_model.onnx');
  final decoderPath = p.join(modelDir, 'decoder_model.onnx');
  final srcSpmPath  = p.join(modelDir, 'tokenizer', 'source.spm');
  final tgtSpmPath  = p.join(modelDir, 'tokenizer', 'target.spm');

  // ── 토크나이저 ──────────────────────────────────────────────
  final inputIds = await _spEncode(srcSpmPath, inputText);
  if (inputIds.isEmpty) return inputText;

  // ── 인코더 ──────────────────────────────────────────────────
  final encoder = _loadSession(encoderPath);

  final inputIdsTensor = OrtValueTensor.createTensorWithDataList(
    Int64List.fromList(inputIds),
    [1, inputIds.length],
  );
  final attnMaskTensor = OrtValueTensor.createTensorWithDataList(
    Int64List.fromList(List.filled(inputIds.length, 1)),
    [1, inputIds.length],
  );

  final encOutputs = encoder.run(OrtRunOptions(), {
    'input_ids':      inputIdsTensor,
    'attention_mask': attnMaskTensor,
  });

  // encoder 출력: last_hidden_state [1, enc_seq_len, hidden_size]
  final hiddenRaw = encOutputs[0]?.value as List;
  final encSeqLen = (hiddenRaw[0] as List).length;
  final hiddenSize = ((hiddenRaw[0] as List)[0] as List).length;

  // [1, enc_seq_len, hidden_size] → Float32List
  final hiddenFlat = Float32List(encSeqLen * hiddenSize);
  for (int i = 0; i < encSeqLen; i++) {
    final row = (hiddenRaw[0] as List)[i] as List;
    for (int j = 0; j < hiddenSize; j++) {
      hiddenFlat[i * hiddenSize + j] = (row[j] as num).toDouble();
    }
  }

  inputIdsTensor.release();
  attnMaskTensor.release();
  encOutputs.forEach((v) => v?.release());

  // ── 디코더 (greedy decoding) ─────────────────────────────────
  final decoder = _loadSession(decoderPath);
  // MarianMT: pad_token_id(65000) 을 decoder 시작 토큰으로 사용
  const int bosId = 65000;
  const int eosId = 0;
  final List<int> generated = [bosId];

  for (int step = 0; step < AppConfig.maxOutputLength; step++) {
    final decInputTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(generated),
      [1, generated.length],
    );
    final encHiddenTensor = OrtValueTensor.createTensorWithDataList(
      hiddenFlat,
      [1, encSeqLen, hiddenSize],
    );
    final encAttnTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(List.filled(encSeqLen, 1)),
      [1, encSeqLen],
    );

    final decOutputs = decoder.run(OrtRunOptions(), {
      'input_ids':               decInputTensor,
      'encoder_hidden_states':   encHiddenTensor,
      'encoder_attention_mask':  encAttnTensor,
    });

    // logits: [1, seq_len, vocab_size]
    final logitsRaw   = decOutputs[0]?.value as List;
    final lastLogits  = (logitsRaw[0] as List).last as List;

    // argmax
    int nextToken = 0;
    double maxVal = double.negativeInfinity;
    for (int i = 0; i < lastLogits.length; i++) {
      final v = (lastLogits[i] as num).toDouble();
      if (v > maxVal) { maxVal = v; nextToken = i; }
    }

    decInputTensor.release();
    encHiddenTensor.release();
    encAttnTensor.release();
    decOutputs.forEach((v) => v?.release());

    if (nextToken == eosId) break;
    generated.add(nextToken);
  }

  // ── 디토크나이저 ─────────────────────────────────────────────
  final outputIds = generated.sublist(1); // BOS 제거
  return _spDecode(tgtSpmPath, outputIds);
}

/// 공개 번역 함수 — 피벗 경유 자동 처리
Future<String> translate({
  required String text,
  required String srcLang,
  required String dstLang,
}) async {
  if (srcLang == dstLang || text.trim().isEmpty) return text;

  final route = translationRoute(srcLang, dstLang);
  if (route.isEmpty) return text;

  final mm = ModelManager.instance;
  String current = text;

  for (final modelName in route) {
    final dir = await mm.modelPath(modelName);
    current = await _translateWithModel(modelDir: dir, inputText: current);
  }

  return current;
}

/// ONNX 세션 전체 해제 (메모리 정리)
void releaseAllSessions() {
  for (final s in _sessionCache.values) {
    s.release();
  }
  _sessionCache.clear();
}
