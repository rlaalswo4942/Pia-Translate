import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/translation_record.dart';

/// Pia 음성 보조 학습용 번역 데이터 수집 서비스
///
/// 사용자 동의 기반 익명 수집 → 로컬 SQLite 저장 → JSONL 내보내기
/// PII 없음: 텍스트 쌍만 기록 (디바이스 ID, 위치 등 일절 없음)
class DataCollector {
  static final DataCollector instance = DataCollector._();
  DataCollector._();

  static const _kConsentKey  = 'pia_data_consent';
  static const _kDbFile      = 'pia_training.db';
  static const _kExportFile  = 'pia_training_data.jsonl';
  static const _kTableName   = 'translations';

  Database? _db;
  bool _consentGiven = false;
  bool _hasAnswered  = false;

  bool get consentGiven => _consentGiven;
  bool get hasAnswered  => _hasAnswered;

  // ── 초기화 (앱 시작 시 1회) ─────────────────────────────────
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _hasAnswered  = prefs.containsKey(_kConsentKey);
    _consentGiven = prefs.getBool(_kConsentKey) ?? false;
    if (_consentGiven) await _openDb();
  }

  // ── 사용자 동의 설정 ─────────────────────────────────────────
  Future<void> setConsent(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kConsentKey, value);
    _consentGiven = value;
    _hasAnswered  = true;
    if (value) {
      await _openDb();
    } else {
      await _db?.close();
      _db = null;
    }
  }

  // ── DB 열기 ──────────────────────────────────────────────────
  Future<void> _openDb() async {
    if (_db != null) return;
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, _kDbFile);
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE $_kTableName (
          id               TEXT PRIMARY KEY,
          timestamp        TEXT NOT NULL,
          input_type       TEXT NOT NULL,
          src_lang         TEXT NOT NULL,
          dst_lang         TEXT NOT NULL,
          source_text      TEXT NOT NULL,
          translated_text  TEXT NOT NULL,
          stt_raw          TEXT,
          ocr_raw          TEXT
        )
      '''),
    );
  }

  // ── 번역 1건 기록 ────────────────────────────────────────────
  Future<void> record({
    required String inputType,   // 'text' | 'voice' | 'image'
    required String srcLang,
    required String dstLang,
    required String sourceText,
    required String translatedText,
    String? sttRaw,
    String? ocrRaw,
  }) async {
    if (!_consentGiven || _db == null) return;
    if (sourceText.trim().isEmpty || translatedText.trim().isEmpty) return;

    final rec = TranslationRecord(
      id:             const Uuid().v4(),
      timestamp:      DateTime.now(),
      inputType:      inputType,
      srcLang:        srcLang,
      dstLang:        dstLang,
      sourceText:     sourceText,
      translatedText: translatedText,
      sttRaw:         sttRaw,
      ocrRaw:         ocrRaw,
    );
    await _db!.insert(_kTableName, rec.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── 통계 ─────────────────────────────────────────────────────
  Future<int> recordCount() async {
    if (_db == null) return 0;
    final result = await _db!.rawQuery('SELECT COUNT(*) FROM $_kTableName');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<String, int>> countByType() async {
    if (_db == null) return {};
    final rows = await _db!.rawQuery(
        'SELECT input_type, COUNT(*) as cnt FROM $_kTableName GROUP BY input_type');
    return {for (final r in rows) r['input_type'] as String: r['cnt'] as int};
  }

  // ── JSONL 내보내기 (Pia 학습 데이터) ─────────────────────────
  /// 반환값: 내보낸 파일 경로 (공유/전송에 사용)
  Future<String?> exportJsonl() async {
    if (_db == null) return null;
    final rows = await _db!.query(_kTableName, orderBy: 'timestamp ASC');
    if (rows.isEmpty) return null;

    final lines = rows.map((r) => jsonEncode(r)).join('\n');
    final docs  = await getApplicationDocumentsDirectory();
    final path  = p.join(docs.path, _kExportFile);
    await File(path).writeAsString(lines, flush: true);
    return path;
  }

  // ── 데이터 삭제 ──────────────────────────────────────────────
  Future<void> deleteAll() async {
    if (_db == null) return;
    await _db!.delete(_kTableName);
  }
}
