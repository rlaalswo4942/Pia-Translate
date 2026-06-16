/// STT 인식 결과 텍스트 정규화
/// Vosk 출력은 구두점 없음, 띄어쓰기 오류 가능 — 기본 클린업 수행
class TextNormalizer {
  static final _multiSpace = RegExp(r' {2,}');

  // 한국어 음성 필러 패턴 (단독 등장 시 제거)
  static final _koFillers = RegExp(
    r'\b(음+|어+|그+|아+|저+|뭐+|네+|예+)\b',
    unicode: true,
  );

  /// [raw]      : Vosk 원시 출력
  /// [langCode] : 입력 언어 코드 (ko, en, ja, zh, fr)
  static String normalize(String raw, {String langCode = 'ko'}) {
    String t = raw.trim();
    if (t.isEmpty) return t;

    // 다중 공백 → 단일 공백
    t = t.replaceAll(_multiSpace, ' ');

    if (langCode == 'ko') {
      // 한국어: 단독 필러 단어 제거 후 재정리
      t = t.replaceAll(_koFillers, '').replaceAll(_multiSpace, ' ').trim();
    } else if (langCode == 'en' || langCode == 'fr') {
      // 영어/프랑스어: 첫 글자 대문자
      if (t.isNotEmpty) t = t[0].toUpperCase() + t.substring(1);
    }

    return t;
  }
}
