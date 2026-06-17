/// Pia 학습 데이터 단위 — 번역 1건의 완전한 기록
class TranslationRecord {
  final String id;
  final DateTime timestamp;
  final String inputType;       // 'text' | 'voice' | 'image'
  final String srcLang;
  final String dstLang;
  final String sourceText;
  final String translatedText;
  final String? sttRaw;         // STT 원문 (정규화 이전)
  final String? ocrRaw;         // OCR 원문

  const TranslationRecord({
    required this.id,
    required this.timestamp,
    required this.inputType,
    required this.srcLang,
    required this.dstLang,
    required this.sourceText,
    required this.translatedText,
    this.sttRaw,
    this.ocrRaw,
  });

  Map<String, dynamic> toMap() => {
    'id':               id,
    'timestamp':        timestamp.toIso8601String(),
    'input_type':       inputType,
    'src_lang':         srcLang,
    'dst_lang':         dstLang,
    'source_text':      sourceText,
    'translated_text':  translatedText,
    'stt_raw':          sttRaw,
    'ocr_raw':          ocrRaw,
  };

  factory TranslationRecord.fromMap(Map<String, dynamic> m) => TranslationRecord(
    id:             m['id'] as String,
    timestamp:      DateTime.parse(m['timestamp'] as String),
    inputType:      m['input_type'] as String,
    srcLang:        m['src_lang'] as String,
    dstLang:        m['dst_lang'] as String,
    sourceText:     m['source_text'] as String,
    translatedText: m['translated_text'] as String,
    sttRaw:         m['stt_raw'] as String?,
    ocrRaw:         m['ocr_raw'] as String?,
  );
}
