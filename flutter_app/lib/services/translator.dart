import '../core/languages.dart';

// onnxruntime 일시 제거 (시작 크래시 원인 격리 중)
// 번역 기능은 추후 호환 버전 확인 후 복원 예정

/// 공개 번역 함수 — 모델 미탑재 시 스텁 반환
Future<String> translate({
  required String text,
  required String srcLang,
  required String dstLang,
}) async {
  if (srcLang == dstLang || text.trim().isEmpty) return text;

  final route = translationRoute(srcLang, dstLang);
  if (route.isEmpty) return text;

  // 번역 모델이 현재 비활성화 상태
  return '⚠️ 번역 모델 준비 중\n(다음 업데이트에서 활성화)';
}

/// ONNX 세션 해제 (stub — 세션 없음)
void releaseAllSessions() {}
