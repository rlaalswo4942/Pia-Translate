// google_mlkit_text_recognition 일시 제거 (시작 크래시 원인 격리 중)

class OcrService {
  static OcrService? _instance;
  static OcrService get instance => _instance ??= OcrService._();
  OcrService._();

  Future<String> recognize(String imagePath, String langCode) async {
    return '⚠️ OCR 기능 준비 중';
  }

  void dispose() {}
}
