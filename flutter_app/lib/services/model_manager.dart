import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/config.dart';
import '../core/languages.dart';
import 'app_logger.dart';

final _L = AppLogger.instance;

// 백그라운드 isolate에서 ZIP 추출 — Process.run 없이 순수 Dart로 처리
// (Android SELinux가 서브프로세스 실행을 차단하는 문제 해결)
void _extractZipIsolate(Map<String, String> args) {
  final zipPath       = args['zipPath']!;
  final destDir       = args['destDir']!;
  final canonicalDest = args['canonicalDest']!;
  // 경로 비교 시 trailing separator 보장 (Zip Slip 오탐 방지)
  final prefix = canonicalDest.endsWith('/') ? canonicalDest : '$canonicalDest/';

  final inputStream = InputFileStream(zipPath);
  final archive = ZipDecoder().decodeBuffer(inputStream);

  for (final file in archive) {
    // canonicalDest 기준으로 경로 구성 — Android에서 /data/user/0 ↔ /data/data 심볼릭 링크
    // 오탐 방지: destDir(심볼릭 링크 경로)가 아닌 canonicalDest(실제 경로)로 비교
    final outPath = p.normalize(p.join(canonicalDest, file.name));

    // Zip Slip 방지: 추출 경로가 destDir 하위인지 확인
    if (outPath != canonicalDest && !outPath.startsWith(prefix)) {
      inputStream.closeSync();
      throw Exception('Zip Slip 감지: ${file.name}');
    }

    if (file.isFile) {
      File(outPath).createSync(recursive: true);
      final out = OutputFileStream(outPath);
      file.writeContent(out);
      out.closeSync();
    } else {
      Directory(outPath).createSync(recursive: true);
    }
  }
  inputStream.closeSync();
}

/// 모델 파일 관리 — 다운로드, 무결성 검증, 압축 해제
class ModelManager {
  static ModelManager? _instance;
  static ModelManager get instance => _instance ??= ModelManager._();
  ModelManager._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 10),
  ));
  String? _modelDir;

  // 다운로드 진행 콜백: (modelName, progress 0.0~1.0)
  void Function(String, double)? onProgress;

  Future<String> get modelDir async {
    if (_modelDir != null) return _modelDir!;
    final docs = await getApplicationDocumentsDirectory();
    _modelDir = p.join(docs.path, AppConfig.modelSubDir);
    await Directory(_modelDir!).create(recursive: true);
    return _modelDir!;
  }

  Future<String> modelPath(String modelName) async =>
      p.join(await modelDir, modelName);

  Future<bool> isDownloaded(String modelName) async {
    final dir = await modelPath(modelName);
    return File(p.join(dir, '.ready')).existsSync();
  }

  Future<bool> isRouteReady(String src, String dst) async {
    for (final model in translationRoute(src, dst)) {
      if (!await isDownloaded(model)) return false;
    }
    return true;
  }

  Future<void> ensureModels(List<String> modelNames) async {
    for (final name in modelNames) {
      if (!await isDownloaded(name)) await downloadModel(name);
    }
  }

  /// 단일 모델 다운로드 + 무결성 검증 + 압축 해제 (이어받기 + 자동 재시도 3회)
  Future<void> downloadModel(String modelName, {String? url}) async {
    final effectiveUrl = url ?? '${AppConfig.modelBaseUrl}/$modelName.zip';

    // ── 보안 ①: 허용 도메인 검증 ──────────────────────────────
    _assertAllowedUrl(effectiveUrl);

    final dir     = await modelDir;
    final destDir = Directory(p.join(dir, modelName));
    final zipPath = p.join(dir, '$modelName.zip');

    await destDir.create(recursive: true);

    Object? lastError;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        // ── 이어받기 스트리밍 다운로드 ──────────────────────────
        await _downloadWithResume(effectiveUrl, zipPath, modelName);
        _L.log('DL', '$modelName 다운로드 완료 → 압축 해제 시작');

        // ── 보안 ②: SHA256 무결성 검증 ──────────────────────────
        await _verifyChecksum(zipPath, modelName);

        // ── 보안 ③: 순수 Dart ZIP 추출 (백그라운드 isolate) ──────
        await _safeExtractZip(zipPath, destDir.path);
        _L.log('DL', '$modelName 압축 해제 완료');

        await File(p.join(destDir.path, '.ready')).create();
        _L.log('DL', '$modelName 준비 완료 ✓');
        _deleteIfExists(zipPath);
        return; // 성공
      } on SecurityException {
        _deleteIfExists(zipPath);
        rethrow; // 보안 오류는 재시도 없이 즉시 전파
      } catch (e) {
        lastError = e;
        _L.log('ERR', '$modelName 실패: $e');
        // 무결성/ZIP 오류 → 손상된 파일 삭제 후 처음부터 재다운로드
        // 네트워크 오류 → 부분 파일 유지해서 다음 시도에서 이어받기
        final msg = e.toString().toLowerCase();
        if (msg.contains('무결성') || msg.contains('zip') || msg.contains('slip')) {
          _deleteIfExists(zipPath);
        }
      }
    }

    _deleteIfExists(zipPath);
    throw Exception('$modelName 다운로드 실패 (3회 시도): $lastError');
  }

  void _deleteIfExists(String path) {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }

  // ── 이어받기 지원 스트리밍 다운로드 ───────────────────────────────
  // Dio 대신 dart:io HttpClient 사용: 리다이렉트를 직접 따라가며 Range 헤더 유지
  // Dio는 리다이렉트 시 Range 헤더를 버려 이어받기가 불가능함
  Future<void> _downloadWithResume(
      String url, String zipPath, String modelName) async {
    final file      = File(zipPath);
    final startByte = file.existsSync() ? file.lengthSync() : 0;

    final client = HttpClient()..autoUncompress = false;
    try {
      // 리다이렉트를 직접 추적하며 Range 헤더 보존
      Uri uri = Uri.parse(url);
      HttpClientResponse? response;
      for (int hop = 0; hop < 10; hop++) {
        final req = await client.getUrl(uri);
        if (startByte > 0) req.headers.set('Range', 'bytes=$startByte-');
        req.headers.set('User-Agent', 'PiaTranslate/1.0 Dart');
        final res = await req.close();

        if (res.isRedirect) {
          final location = res.headers.value('location');
          if (location == null) { await res.drain<void>(); break; }
          uri = uri.resolve(location);
          await res.drain<void>();
          continue;
        }
        response = res;
        break;
      }

      if (response == null) throw Exception('리다이렉트 해결 실패');
      if (response.statusCode != 200 && response.statusCode != 206) {
        await response.drain<void>();
        throw Exception('HTTP ${response.statusCode}');
      }

      final isPartial = response.statusCode == 206;
      final mode      = (startByte > 0 && isPartial) ? FileMode.append : FileMode.write;

      // 전체 파일 크기 계산 (진행률 표시용)
      int total = 0;
      if (isPartial) {
        final cr = response.headers.value('content-range');
        if (cr != null) {
          final m = RegExp(r'/(\d+)').firstMatch(cr ?? '');
          if (m != null) total = int.parse(m.group(1)!);
        }
      } else {
        if (response.contentLength > 0) total = response.contentLength;
      }

      final sink     = file.openWrite(mode: mode);
      int   received = isPartial ? startByte : 0;

      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(modelName, received / total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  // ── 보안 ①: URL 허용 목록 검사 ────────────────────────────────
  void _assertAllowedUrl(String url) {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') {
      throw SecurityException('HTTP 다운로드는 허용되지 않습니다: $url');
    }
    final host = uri.host;
    final allowed = AppConfig.allowedDownloadHosts
        .any((h) => host == h || host.endsWith('.$h'));
    if (!allowed) {
      throw SecurityException('허용되지 않은 다운로드 도메인: $host');
    }
  }

  // ── 보안 ②: SHA256 해시 검증 ──────────────────────────────────
  Future<void> _verifyChecksum(String filePath, String modelName) async {
    final expected = AppConfig.modelSha256[modelName];
    if (expected == null) return;

    final bytes  = await File(filePath).readAsBytes();
    final actual = sha256.convert(bytes).toString();
    if (actual != expected) {
      throw SecurityException(
        '모델 파일 무결성 검증 실패 ($modelName)\n'
        '예상: $expected\n실제: $actual',
      );
    }
  }

  // ── 보안 ③: 백그라운드 isolate에서 ZIP 추출 ────────────────────
  // Process.run('unzip') 대신 순수 Dart archive 패키지 사용
  // → Android SELinux 서브프로세스 제한 우회, 메인 스레드 차단 없음
  Future<void> _safeExtractZip(String zipPath, String destDir) async {
    final canonicalDest = Directory(destDir).resolveSymbolicLinksSync();
    await compute<Map<String, String>, void>(_extractZipIsolate, {
      'zipPath':       zipPath,
      'destDir':       destDir,
      'canonicalDest': canonicalDest,
    });
  }

  Future<List<String>> downloadedModels() async {
    final dir = Directory(await modelDir);
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<Directory>()
        .where((d) => File(p.join(d.path, '.ready')).existsSync())
        .map((d) => p.basename(d.path))
        .toList();
  }

  Future<double> totalCacheMb() async {
    final dir = Directory(await modelDir);
    if (!dir.existsSync()) return 0;
    int bytes = 0;
    await for (final f in dir.list(recursive: true)) {
      if (f is File) bytes += await f.length();
    }
    return bytes / 1024 / 1024;
  }

  Future<void> deleteModel(String modelName) async {
    final dir = Directory(await modelPath(modelName));
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

/// 보안 위반 예외
class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}
