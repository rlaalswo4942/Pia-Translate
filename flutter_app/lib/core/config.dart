/// 앱 설정 — 모델 다운로드 URL 및 경로 설정

class AppConfig {
  // ── 모델 다운로드 ────────────────────────────────────────────
  // GitHub Release 'models-v1' 에 업로드된 ONNX ZIP 파일
  static const String modelBaseUrl =
      'https://github.com/rlaalswo4942/Pia-Translate/releases/download/models-v1';

  // ── 보안: 허용 다운로드 도메인 ───────────────────────────────
  // 이 목록에 없는 도메인에서의 다운로드는 모두 차단
  static const List<String> allowedDownloadHosts = [
    'github.com',                   // 번역 모델 (GitHub Releases)
    'objects.githubusercontent.com', // GitHub CDN (Releases 리디렉션 대상)
    'alphacephei.com',              // Vosk 음성 인식 모델
    'huggingface.co',               // 예비 (HuggingFace 직접 업로드 시)
  ];

  // ── 보안: 모델별 SHA256 해시 (무결성 검증) ───────────────────
  // 모델 변환 & 업로드 후 sha256sum <file>.zip 으로 확인 후 채워 넣을 것
  // null = 해시 검증 건너뜀 (배포 전 임시 허용)
  static const Map<String, String?> modelSha256 = {
    'ko_en':   null,
    'en_ko':   null,
    'en_ja':   null,
    'ja_en':   null,
    'en_zh':   null,
    'zh_en':   null,
    'en_fr':   null,
    'fr_en':   null,
    'vosk_ko': null,
  };

  // ── 입력 제한 ────────────────────────────────────────────────
  static const int maxInputChars = 2000;

  // ── 앱 정보 ──────────────────────────────────────────────────
  static const String appName    = 'Pia 번역';
  static const String appVersion = '1.0.0';

  // ── 추론 설정 ────────────────────────────────────────────────
  static const int maxOutputLength = 256;
  static const int beamSize        = 1;    // greedy decoding (속도 우선)
  static const double lengthPenalty = 0.6;

  // ── 캐시 ─────────────────────────────────────────────────────
  static const String modelSubDir = 'translate_models';

  // ── Vosk STT ─────────────────────────────────────────────────
  static const String voskModelName = 'vosk_ko';
  static const String voskModelUrl  =
      'https://alphacephei.com/vosk/models/vosk-model-ko-0.22.zip';
}
