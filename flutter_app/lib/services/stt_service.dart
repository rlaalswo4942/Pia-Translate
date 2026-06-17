import 'package:speech_to_text/speech_to_text.dart';
import '../core/config.dart';

/// 기기 내장 STT 서비스 (speech_to_text)
/// 별도 모델 다운로드 없이 Android 내장 음성 인식 사용
class SttService {
  static SttService? _instance;
  static SttService get instance => _instance ??= SttService._();
  SttService._();

  final _stt = SpeechToText();
  bool _initialized = false;
  bool _listening   = false;

  bool get isModelLoaded => _initialized;
  bool get isListening   => _listening;

  // SpeechToText는 별도 다운로드 불필요 — 항상 ready
  Future<void> ensureModel({void Function(double)? onProgress}) async {
    if (_initialized) return;
    onProgress?.call(0.5);
    _initialized = await _stt.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
    onProgress?.call(1.0);
  }

  /// 언어 코드를 STT locale ID로 변환
  String _localeId(String langCode) {
    const map = {
      'ko': 'ko-KR',
      'en': 'en-US',
      'ja': 'ja-JP',
      'zh': 'zh-CN',
      'fr': 'fr-FR',
    };
    return map[langCode] ?? 'ko-KR';
  }

  /// 녹음 시작 — 결과를 onResult 콜백으로 스트리밍
  Future<void> startListening({
    required String langCode,
    required void Function(String partial) onPartial,
    required void Function(String result) onResult,
  }) async {
    if (!_initialized) await ensureModel();
    if (!_initialized) {
      onResult('음성 인식을 사용할 수 없습니다.');
      return;
    }

    _listening = true;
    await _stt.listen(
      localeId: _localeId(langCode),
      listenMode: ListenMode.dictation,
      pauseFor: const Duration(seconds: 2),
      onResult: (r) {
        if (r.finalResult) {
          _listening = false;
          onResult(r.recognizedWords);
        } else {
          onPartial(r.recognizedWords);
        }
      },
    );
  }

  Future<void> stopListening() async {
    _listening = false;
    await _stt.stop();
  }

  void dispose() {
    _stt.cancel();
    _listening = false;
  }
}
