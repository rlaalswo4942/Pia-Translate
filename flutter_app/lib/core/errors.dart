/// 앱 전역 예외 타입 — 각 서비스는 이 타입만 던짐

class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}

class ModelException implements Exception {
  final String message;
  const ModelException(this.message);
  @override
  String toString() => 'ModelException: $message';
}

class TranslationException implements Exception {
  final String message;
  const TranslationException(this.message);
  @override
  String toString() => 'TranslationException: $message';
}

class OcrException implements Exception {
  final String message;
  const OcrException(this.message);
  @override
  String toString() => 'OcrException: $message';
}

class SttException implements Exception {
  final String message;
  const SttException(this.message);
  @override
  String toString() => 'SttException: $message';
}
