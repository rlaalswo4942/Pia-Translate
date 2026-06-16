/// TTS 서비스 — 인터페이스만 정의, 구현은 추후 연결
///
/// 연결 방법 (추후):
///   1. pubspec.yaml 에 flutter_tts: ^4.x.x 추가
///   2. isAvailable 을 true 로 변경
///   3. speak() 에 FlutterTts 호출 구현
class TtsService {
  static TtsService? _instance;
  static TtsService get instance => _instance ??= TtsService._();
  TtsService._();

  /// TTS 활성 여부 — 구현 완료 시 true 로 교체
  bool get isAvailable => false;

  /// 번역 결과를 목적 언어로 읽어주기
  /// [text]    : 읽을 텍스트
  /// [langCode]: 언어 코드 (ko, en, ja, zh, fr)
  Future<void> speak(String text, String langCode) async {
    if (!isAvailable || text.trim().isEmpty) return;
    // TODO: FlutterTts().setLanguage(_toLocale(langCode)) + .speak(text)
  }

  Future<void> stop() async {
    // TODO: FlutterTts().stop()
  }

  // ignore: unused_element
  String _toLocale(String code) {
    const map = {
      'ko': 'ko-KR',
      'en': 'en-US',
      'ja': 'ja-JP',
      'zh': 'zh-CN',
      'fr': 'fr-FR',
    };
    return map[code] ?? code;
  }
}
