import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/config.dart';
import '../core/languages.dart';

// 백그라운드 isolate에서 ZIP 추출 — Process.run 없이 순수 Dart로 처리
// (Android SELinux가 서브프로세스 실행을 차단하는 문제 해결)
void _extractZipIsolate(Map<String, String> args) {
  final zipPath       = args['zipPath']!;
  final destDir       = args['destDir']!;
  final canonicalDest = args['canonicalDest']!;
  // 경로 비교 시 trailing separator 보장 (Zip Slip 오탐 방지)
  final prefix = canonicalDest.endsWith('/') ? canonicalDest : '$canonicalDest/';

  final inputStream = InputFileStream(zipPath);
  final archive = ZipDecoder().decodeStream(inputStream);

  for (final file in archive) {
    final outPath = p.normalize(p.join(destDir, file.name));

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

  /// 단일 모델 다운로드 + 무결성 검증 + 압축 해제
  Future<void> downloadModel(String modelName, {String? url}) async {
    final effectiveUrl = url ?? '${AppConfig.modelBaseUrl}/$modelName.zip';

    // ── 보안 ①: 허용 도메인 검증 ──────────────────────────────
    _assertAllowedUrl(effectiveUrl);

    final dir     = await modelDir;
    final destDir = Directory(p.join(dir, modelName));
    final zipPath = p.join(dir, '$modelName.zip');

    await destDir.create(recursive: true);

    try {
      await _dio.download(
        effectiveUrl,
        zipPath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(modelName, received / total);
        },
      );

      // ── 보안 ②: SHA256 무결성 검증 ──────────────────────────
      await _verifyChecksum(zipPath, modelName);

      // ── 보안 ③: 순수 Dart ZIP 추출 (백그라운드 isolate) ──────
      await _safeExtractZip(zipPath, destDir.path);

      await File(p.join(destDir.path, '.ready')).create();
    } finally {
      final zip = File(zipPath);
      if (zip.existsSync()) await zip.delete();
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
