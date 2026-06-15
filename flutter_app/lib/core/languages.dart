/// 지원 언어 정의 및 번역 라우팅
class Language {
  final String code;
  final String name;
  final String nameEn;
  final String flag;

  const Language({
    required this.code,
    required this.name,
    required this.nameEn,
    required this.flag,
  });
}

const List<Language> kSupportedLanguages = [
  Language(code: 'ko', name: '한국어', nameEn: 'Korean',  flag: '🇰🇷'),
  Language(code: 'en', name: '영어',   nameEn: 'English', flag: '🇺🇸'),
  Language(code: 'ja', name: '일본어', nameEn: 'Japanese',flag: '🇯🇵'),
  Language(code: 'zh', name: '중국어', nameEn: 'Chinese', flag: '🇨🇳'),
  Language(code: 'fr', name: '프랑스어',nameEn: 'French',  flag: '🇫🇷'),
];

Language languageOf(String code) =>
    kSupportedLanguages.firstWhere((l) => l.code == code,
        orElse: () => kSupportedLanguages.first);

/// 번역에 필요한 모델 디렉토리 이름 목록
/// 영어를 피벗으로 사용: ko↔en 직접, 나머지는 ko→en→X 경유
const List<String> kRequiredModels = [
  'ko_en', // 한→영 (기준)
  'en_ko', // 영→한 (기준)
  'en_ja', // 영→일 (ko→ja 피벗)
  'ja_en', // 일→영 (ja→ko 피벗)
  'en_zh', // 영→중 (ko→zh 피벗)
  'zh_en', // 중→영 (zh→ko 피벗)
  'en_fr', // 영→불 (ko→fr 피벗)
  'fr_en', // 불→영 (fr→ko 피벗)
];

/// 번역 경로: (src, dst) → 사용할 모델 순서
List<String> translationRoute(String src, String dst) {
  if (src == dst) return [];
  if (src == 'ko' && dst == 'en') return ['ko_en'];
  if (src == 'en' && dst == 'ko') return ['en_ko'];
  if (src == 'ko') return ['ko_en', 'en_$dst'];   // ko → en → dst
  if (dst == 'ko') return ['${src}_en', 'en_ko']; // src → en → ko
  // X → Y (둘 다 비영어): X → en → Y
  return ['${src}_en', 'en_$dst'];
}
