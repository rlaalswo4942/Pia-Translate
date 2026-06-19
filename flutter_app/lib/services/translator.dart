import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import '../core/config.dart';
import '../core/languages.dart';
import 'model_manager.dart';

const _channel = MethodChannel('com.pia.translate/sentencepiece');

final _sessionCache = <String, OrtSession>{};

OrtSession _loadSession(String modelPath) {
  return _sessionCache.putIfAbsent(modelPath, () {
    return OrtSession.fromFile(modelPath, OrtSessionOptions());
  });
}

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

Future<String> _translateWithModel({
  required String modelDir,
  required String inputText,
}) async {
  final encoderPath = p.join(modelDir, 'encoder_model.onnx');
  final decoderPath = p.join(modelDir, 'decoder_model.onnx');
  final srcSpmPath  = p.join(modelDir, 'tokenizer', 'source.spm');
  final tgtSpmPath  = p.join(modelDir, 'tokenizer', 'target.spm');

  final inputIds = await _spEncode(srcSpmPath, inputText);
  if (inputIds.isEmpty) return inputText;

  final encoder = _loadSession(encoderPath);

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

  final decoder = _loadSession(decoderPath);
  const int bosId = 65000;
  const int eosId = 0;
  final List<int> generated = [bosId];

  for (int step = 0; step < AppConfig.maxOutputLength; step++) {
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

  return _spDecode(tgtSpmPath, generated.sublist(1));
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
    final dir = await mm.modelPath(modelName);
    current = await _translateWithModel(modelDir: dir, inputText: current);
  }
  return current;
}

void releaseAllSessions() {
  for (final s in _sessionCache.values) { s.release(); }
  _sessionCache.clear();
}
