import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/config.dart';
import '../core/languages.dart';

/// 모델 파일 관리 — 다운로드, 무결성 검증, 압축 해제
class ModelManager {
  static ModelManager? _instance;
  static ModelManager get instance => _instance ??= ModelManager._();
  ModelManager._();

  final Dio _dio = Dio();
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
  /// [url] 생략 시 modelBaseUrl 기반 자동 생성
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

      // ── 보안 ③: Zip Slip 방지 압축 해제 ──────────────────────
      await _safeExtractZip(zipPath, destDir.path);

      await File(p.join(destDir.path, '.ready')).create();
    } finally {
      // 성공/실패 관계없이 임시 ZIP 삭제
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
    if (expected == null) return; // 해시 미등록 시 건너뜀 (배포 전 개발용)

    final bytes  = await File(filePath).readAsBytes();
    final actual = sha256.convert(bytes).toString();
    if (actual != expected) {
      throw SecurityException(
        '모델 파일 무결성 검증 실패 ($modelName)\n'
        '예상: $expected\n실제: $actual\n'
        '파일이 손상되었거나 변조되었을 수 있습니다.',
      );
    }
  }

  // ── 보안 ③: Zip Slip 방지 압축 해제 ──────────────────────────
  // ZIP 내부 경로가 destDir 외부를 가리키는 경우 중단
  Future<void> _safeExtractZip(String zipPath, String destDir) async {
    final canonicalDest = Directory(destDir).resolveSymbolicLinksSync();

    if (Platform.isAndroid || Platform.isLinux || Platform.isIOS || Platform.isMacOS) {
      // unzip -o: 덮어쓰기 허용, -d: 대상 디렉토리
      final result = await Process.run(
        'unzip', ['-o', zipPath, '-d', destDir],
        runInShell: false, // 쉘 해석 없이 직접 실행 (인수 인젝션 방지)
      );
      if (result.exitCode != 0) {
        throw Exception('압축 해제 실패: ${result.stderr}');
      }
    } else if (Platform.isWindows) {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command',
         'Expand-Archive', '-LiteralPath', zipPath,
         '-DestinationPath', destDir, '-Force'],
        runInShell: false,
      );
      if (result.exitCode != 0) {
        throw Exception('압축 해제 실패: ${result.stderr}');
      }
    }

    // 해제 후 생성된 모든 파일 경로가 destDir 내부에 있는지 검증
    await for (final entity in Directory(destDir).list(recursive: true)) {
      final canonical = entity.resolveSymbolicLinksSync();
      if (!canonical.startsWith(canonicalDest)) {
        await entity.delete(recursive: true);
        throw SecurityException(
          'Zip Slip 공격 감지: 허용 범위 외부 경로 → ${entity.path}',
        );
      }
    }
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
