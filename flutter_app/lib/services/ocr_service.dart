import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 이미지 텍스트 인식 (ML Kit — 완전 오프라인)
/// 소스 언어에 따라 Korean / Japanese / Chinese / Latin 모델 자동 선택
class OcrService {
  static OcrService? _instance;
  static OcrService get instance => _instance ??= OcrService._();
  OcrService._();

  final _recognizers = <TextRecognitionScript, TextRecognizer>{};

  TextRecognizer _recognizer(String langCode) {
    final script = _scriptFor(langCode);
    return _recognizers.putIfAbsent(script, () => TextRecognizer(script: script));
  }

  TextRecognitionScript _scriptFor(String langCode) {
    switch (langCode) {
      case 'ko': return TextRecognitionScript.korean;
      case 'ja': return TextRecognitionScript.japanese;
      case 'zh': return TextRecognitionScript.chinese;
      default:   return TextRecognitionScript.latin;
    }
  }

  /// [imagePath] 에서 텍스트 인식 후 반환
  /// [langCode] 는 소스 언어 코드 (ko/en/ja/zh/fr)
  Future<String> recognize(String imagePath, String langCode) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final result = await _recognizer(langCode).processImage(inputImage);
    return result.blocks.map((b) => b.text).join('\n').trim();
  }

  void dispose() {
    for (final r in _recognizers.values) {
      r.close();
    }
    _recognizers.clear();
  }
}
