// speech_to_text 제거 — 일부 기기에서 플러그인 등록 단계 hang 유발 가능성
// 음성 인식은 추후 기기 호환성 확인 후 재활성화

class SttService {
  static SttService? _instance;
  static SttService get instance => _instance ??= SttService._();
  SttService._();

  bool get isModelLoaded => false;
  bool get isListening   => false;

  Future<void> ensureModel({void Function(double)? onProgress}) async {}

  Future<void> startListening({
    required String langCode,
    required void Function(String partial) onPartial,
    required void Function(String result) onResult,
  }) async {
    onResult('⚠️ 음성 인식 기능 준비 중 (다음 업데이트에서 활성화)');
  }

  Future<void> stopListening() async {}

  void dispose() {}
}
