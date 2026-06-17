import 'dart:io';
import 'package:vosk_flutter/vosk_flutter.dart';
import '../core/config.dart';
import 'model_manager.dart';

/// Vosk 오프라인 STT 서비스 (vosk_flutter ^0.3.x API)
class SttService {
  static SttService? _instance;
  static SttService get instance => _instance ??= SttService._();
  SttService._();

  Model?         _model;
  Recognizer?    _recognizer;
  SpeechService? _speech;

  bool get isModelLoaded => _model != null;

  Future<void> ensureModel({void Function(double)? onProgress}) async {
    if (_model != null) return;

    final mm = ModelManager.instance;
    if (!await mm.isDownloaded(AppConfig.voskModelName)) {
      mm.onProgress = (_, prog) => onProgress?.call(prog);
      try {
        await mm.downloadModel(
          AppConfig.voskModelName,
          url: AppConfig.voskModelUrl,
        );
      } finally {
        mm.onProgress = null;
      }
    }

    final modelPath = await _findModelDir();
    _model      = await Model.create(modelPath);
    _recognizer = await Recognizer.create(
      model:      _model!,
      sampleRate: 16000,
    );
  }

  /// Vosk ZIP 내부의 단일 서브디렉토리를 모델 경로로 사용
  Future<String> _findModelDir() async {
    final base = Directory(
      await ModelManager.instance.modelPath(AppConfig.voskModelName),
    );
    final subdirs = base.listSync().whereType<Directory>().toList();
    return subdirs.isNotEmpty ? subdirs.first.path : base.path;
  }

  Future<SpeechService> startListening() async {
    await _speech?.stop();
    _speech = await SpeechService.create(_recognizer!);
    await _speech!.start();
    return _speech!;
  }

  Future<void> stopListening() async {
    await _speech?.stop();
    _speech = null;
  }

  void dispose() {
    _speech?.stop();
    _recognizer?.dispose();
    _model?.dispose();
    _model      = null;
    _recognizer = null;
    _speech     = null;
  }
}
