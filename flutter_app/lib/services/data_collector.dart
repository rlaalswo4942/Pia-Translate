import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
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

  static const _kConsentKey    = 'pia_data_consent';
  static const _kDbFile        = 'pia_training.db';
  static const _kExportFile    = 'pia_training_data.jsonl';
  static const _kTableName     = 'translations';
  static const _kCentralUrlKey = 'pia_central_db_url';
  static const _kCentralKeyKey = 'pia_central_db_api_key';

  // 기본값: PC와 같은 Wi-Fi일 때 localhost:3001
  static const _kDefaultUrl = 'http://localhost:3001';

  Database? _db;
  bool _consentGiven = false;
  bool _hasAnswered  = false;
  String _centralUrl    = _kDefaultUrl;
  String _centralApiKey = '';

  bool get consentGiven => _consentGiven;
  bool get hasAnswered  => _hasAnswered;

  // ── 초기화 (앱 시작 시 1회) ─────────────────────────────────
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _hasAnswered  = prefs.containsKey(_kConsentKey);
    _consentGiven = prefs.getBool(_kConsentKey) ?? false;
    _centralUrl    = prefs.getString(_kCentralUrlKey) ?? _kDefaultUrl;
    _centralApiKey = prefs.getString(_kCentralKeyKey) ?? '';
    if (_consentGiven) await _openDb();
  }

  // ── 중앙 DB 설정 ─────────────────────────────────────────────
  Future<void> setCentralDb({required String url, required String apiKey}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCentralUrlKey, url);
    await prefs.setString(_kCentralKeyKey, apiKey);
    _centralUrl    = url;
    _centralApiKey = apiKey;
  }

  String get centralUrl    => _centralUrl;
  String get centralApiKey => _centralApiKey;
  bool   get centralEnabled => _centralApiKey.isNotEmpty;

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

    // 중앙 DB 실시간 동기화 (실패해도 무시)
    _syncToCentral(rec);
  }

  void _syncToCentral(TranslationRecord rec) {
    if (!centralEnabled) return;
    final payload = {
      'transcript':   rec.sourceText,
      'response':     rec.translatedText,
      'notes':        '${rec.srcLang}→${rec.dstLang} [${rec.inputType}]'
                      + (rec.sttRaw != null ? ' stt:${rec.sttRaw}' : '')
                      + (rec.ocrRaw != null ? ' ocr:${rec.ocrRaw}' : ''),
      'tags':         [rec.srcLang, rec.dstLang, rec.inputType],
      'source':       'pia-translate',
      'textCategory': 'TRANSCRIPT',
    };
    http.post(
      Uri.parse('$_centralUrl/api/entries'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key':    _centralApiKey,
      },
      body: jsonEncode(payload),
    ).catchError((_) {});   // 실패 무시
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
