import 'dart:io';
import 'package:vosk_flutter/vosk_flutter.dart';
import '../core/config.dart';
import 'model_manager.dart';

/// Vosk 오프라인 STT 서비스
/// - 모델 다운로드 / 로드 / 녹음 / 결과 반환 담당
class SttService {
  static SttService? _instance;
  static SttService get instance => _instance ??= SttService._();
  SttService._();

  final _vosk = VoskFlutter.instance();
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speech;

  bool get isModelLoaded => _model != null;

  /// 모델이 없으면 다운로드 후 로드
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
    _model = await _vosk.createModel(modelPath);
    _recognizer = await _vosk.createRecognizer(
      model: _model!,
      sampleRate: 16000.0,
    );
  }

  /// Vosk 모델 ZIP 안에 단일 서브디렉토리가 있으므로 그것을 경로로 사용
  Future<String> _findModelDir() async {
    final base = Directory(
      await ModelManager.instance.modelPath(AppConfig.voskModelName),
    );
    final subdirs = base.listSync().whereType<Directory>().toList();
    return subdirs.isNotEmpty ? subdirs.first.path : base.path;
  }

  /// 마이크 녹음 시작 → SpeechService 반환 (스트림으로 결과 수신)
  Future<SpeechService> startListening() async {
    await _speech?.stop();
    _speech = await _vosk.initSpeechService(_recognizer!);
    await _speech!.start();
    return _speech!;
  }

  /// 녹음 중단 → 마지막 결과 flush
  Future<void> stopListening() async {
    await _speech?.stop();
    _speech = null;
  }

  void dispose() {
    _speech?.stop();
    _recognizer?.dispose();
    _model?.dispose();
    _model = null;
    _recognizer = null;
    _speech = null;
  }
}
