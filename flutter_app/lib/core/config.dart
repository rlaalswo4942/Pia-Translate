/// 앱 설정 — 모델 다운로드 URL 및 경로 설정

class AppConfig {
  // ── 모델 다운로드 ────────────────────────────────────────────
  // convert_models.py 실행 후 생성된 모델을 업로드한 주소로 변경
  // 예: HuggingFace Hub, GitHub Releases, 자체 서버
  //
  // URL 형식: {baseUrl}/{modelName}.zip
  // 예: https://huggingface.co/rlaalswo4942/pia-translate-models/resolve/main/ko_en.zip
  static const String modelBaseUrl =
      'https://huggingface.co/rlaalswo4942/pia-translate-models/resolve/main';

  // ── 앱 정보 ─────────────────────────────────────────────────
  static const String appName    = 'Pia 번역';
  static const String appVersion = '1.0.0';

  // ── 추론 설정 ────────────────────────────────────────────────
  static const int maxOutputLength = 256;   // 최대 출력 토큰 수
  static const int beamSize        = 4;     // beam search 크기 (1=greedy)
  static const double lengthPenalty = 0.6;  // 번역 길이 패널티

  // ── 캐시 ─────────────────────────────────────────────────────
  static const String modelSubDir = 'translate_models'; // 앱 문서 디렉토리 내 경로
}
