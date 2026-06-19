import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import '../core/config.dart';
import '../core/languages.dart';
import 'model_manager.dart';

const _channel = MethodChannel('com.pia.translate/sentencepiece');

Future<List<int>> _spEncode(String spModelPath, String text) async {
  final ids = await _channel.invokeMethod<List<dynamic>>(
    'encode',
    {'modelPath': spModelPath, 'text': text},
  );
  return ids?.cast<int>() ?? [];
}

Future<String> _spDecode(String spModelPath, List<int> ids) async {
  final text = await _channel.invokeMethod<String>(
    'decode',
    {'modelPath': spModelPath, 'ids': ids},
  );
  return text ?? '';
}

// ONNX 세션 로딩 + 추론 전용 함수 — compute() isolate에서 실행
// MethodChannel 없음 (background isolate에서 사용 불가)
// 입력: encoderPath, decoderPath, inputIds(List<int>), maxLen(int)
// 출력: 생성된 토큰 ID 리스트 (BOS 제거 전)
List<int> _runOnnxIsolate(Map<String, dynamic> args) {
  final encoderPath = args['encoderPath'] as String;
  final decoderPath = args['decoderPath'] as String;
  final inputIds    = List<int>.from(args['inputIds'] as List);
  final maxLen      = args['maxLen'] as int;

  final encoder = OrtSession.fromFile(File(encoderPath), OrtSessionOptions());

  final inputIdsTensor = OrtValueTensor.createTensorWithDataList(
    Int64List.fromList(inputIds), [1, inputIds.length],
  );
  final attnMaskTensor = OrtValueTensor.createTensorWithDataList(
    Int64List.fromList(List.filled(inputIds.length, 1)), [1, inputIds.length],
  );

  final encOutputs = encoder.run(OrtRunOptions(), {
    'input_ids':      inputIdsTensor,
    'attention_mask': attnMaskTensor,
  });
  encoder.release();

  final hiddenRaw  = encOutputs[0]?.value as List;
  final encSeqLen  = (hiddenRaw[0] as List).length;
  final hiddenSize = ((hiddenRaw[0] as List)[0] as List).length;

  final hiddenFlat = Float32List(encSeqLen * hiddenSize);
  for (int i = 0; i < encSeqLen; i++) {
    final row = (hiddenRaw[0] as List)[i] as List;
    for (int j = 0; j < hiddenSize; j++) {
      hiddenFlat[i * hiddenSize + j] = (row[j] as num).toDouble();
    }
  }
  inputIdsTensor.release();
  attnMaskTensor.release();
  for (final v in encOutputs) { v?.release(); }

  final decoder = OrtSession.fromFile(File(decoderPath), OrtSessionOptions());
  const int bosId = 65000;
  const int eosId = 0;
  final List<int> generated = [bosId];

  for (int step = 0; step < maxLen; step++) {
    final decInputTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(generated), [1, generated.length],
    );
    final encHiddenTensor = OrtValueTensor.createTensorWithDataList(
      hiddenFlat, [1, encSeqLen, hiddenSize],
    );
    final encAttnTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(List.filled(encSeqLen, 1)), [1, encSeqLen],
    );

    final decOutputs = decoder.run(OrtRunOptions(), {
      'input_ids':              decInputTensor,
      'encoder_hidden_states':  encHiddenTensor,
      'encoder_attention_mask': encAttnTensor,
    });

    final logitsRaw  = decOutputs[0]?.value as List;
    final lastLogits = (logitsRaw[0] as List).last as List;

    int nextToken = 0;
    double maxVal = double.negativeInfinity;
    for (int i = 0; i < lastLogits.length; i++) {
      final v = (lastLogits[i] as num).toDouble();
      if (v > maxVal) { maxVal = v; nextToken = i; }
    }
    decInputTensor.release();
    encHiddenTensor.release();
    encAttnTensor.release();
    for (final v in decOutputs) { v?.release(); }

    if (nextToken == eosId) break;
    generated.add(nextToken);
  }
  decoder.release();

  return generated.sublist(1);
}

// opus-mt-en-ROMANCE 같은 다국어 모델에 목표 언어 접두사 반환
String _modelLangPrefix(String modelName, String dstLang) {
  const _romanceModels = {'en_fr', 'en_es', 'en_it', 'en_pt', 'en_ro'};
  if (_romanceModels.contains(modelName)) return '>>$dstLang<< ';
  return '';
}

Future<String> _translateWithModel({
  required String modelDir,
  required String inputText,
}) async {
  final encoderPath = p.join(modelDir, 'encoder_model.onnx');
  final decoderPath = p.join(modelDir, 'decoder_model.onnx');
  final srcSpmPath  = p.join(modelDir, 'tokenizer', 'source.spm');
  final tgtSpmPath  = p.join(modelDir, 'tokenizer', 'target.spm');

  // SentencePiece 인코딩 — 메인 isolate (MethodChannel 필요)
  final inputIds = await _spEncode(srcSpmPath, inputText);
  if (inputIds.isEmpty) return inputText;

  // ONNX 세션 로딩 + 추론 — 백그라운드 isolate
  // OrtSession.fromFile()은 동기 블로킹(수 초) → 메인 스레드에서 실행 시 ANR
  final generatedIds = await compute<Map<String, dynamic>, List<int>>(
    _runOnnxIsolate,
    <String, dynamic>{
      'encoderPath': encoderPath,
      'decoderPath': decoderPath,
      'inputIds':    inputIds,
      'maxLen':      AppConfig.maxOutputLength,
    },
  );

  if (generatedIds.isEmpty) return inputText;

  // SentencePiece 디코딩 — 메인 isolate (MethodChannel 필요)
  return _spDecode(tgtSpmPath, generatedIds);
}

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
    if (!await mm.isDownloaded(modelName)) {
      throw Exception('번역 모델 미다운로드: $modelName — 번역 버튼을 다시 눌러 다운로드하세요.');
    }
    final dir   = await mm.modelPath(modelName);
    final input = _modelLangPrefix(modelName, dstLang) + current;
    current = await _translateWithModel(modelDir: dir, inputText: input);
  }
  return current;
}

// 백그라운드 isolate에서 세션을 생성하므로 메인 스레드에 캐시 없음
// 필요 시 앱 재시작으로 자연 정리됨
void releaseAllSessions() {}
