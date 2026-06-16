/// 앱 설정 — 모델 다운로드 URL 및 경로 설정

class AppConfig {
  // ── 모델 다운로드 ────────────────────────────────────────────
  static const String modelBaseUrl =
      'https://huggingface.co/rlaalswo4942/pia-translate-models/resolve/main';

  // ── 보안: 허용 다운로드 도메인 ───────────────────────────────
  // 이 목록에 없는 도메인에서의 모델 다운로드는 차단됨
  static const List<String> allowedDownloadHosts = [
    'huggingface.co',
    'alphacephei.com',
  ];

  // ── 보안: 모델별 SHA256 해시 (무결성 검증) ───────────────────
  // 모델 파일을 실제로 배포한 후 해시값을 채워 넣을 것
  // sha256sum <model>.zip 으로 확인
  // 값이 null 이면 해시 검증을 건너뜀 (배포 전 임시)
  static const Map<String, String?> modelSha256 = {
    'ko_en':   null, // TODO: 배포 후 실제 해시 입력
    'en_ko':   null,
    'en_ja':   null,
    'ja_en':   null,
    'en_zh':   null,
    'zh_en':   null,
    'en_fr':   null,
    'fr_en':   null,
    'vosk_ko': null, // vosk-model-ko-0.22.zip
  };

  // ── 입력 제한 ─────────────────────────────────────────────────
  static const int maxInputChars = 2000; // 번역 입력 최대 글자 수

  // ── 앱 정보 ─────────────────────────────────────────────────
  static const String appName    = 'Pia 번역';
  static const String appVersion = '1.0.0';

  // ── 추론 설정 ────────────────────────────────────────────────
  static const int maxOutputLength = 256;   // 최대 출력 토큰 수
  static const int beamSize        = 4;     // beam search 크기 (1=greedy)
  static const double lengthPenalty = 0.6;  // 번역 길이 패널티

  // ── 캐시 ─────────────────────────────────────────────────────
  static const String modelSubDir = 'translate_models'; // 앱 문서 디렉토리 내 경로

  // ── Vosk STT ─────────────────────────────────────────────────
  static const String voskModelName = 'vosk_ko';
  static const String voskModelUrl  =
      'https://alphacephei.com/vosk/models/vosk-model-ko-0.22.zip';
}
