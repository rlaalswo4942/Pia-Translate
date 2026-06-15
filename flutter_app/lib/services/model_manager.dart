import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/config.dart';
import '../core/languages.dart';

/// 모델 파일 관리 — 다운로드, 캐시, 압축 해제
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

  /// 모델 디렉토리 경로 (다운로드 완료 가정)
  Future<String> modelPath(String modelName) async =>
      p.join(await modelDir, modelName);

  /// 특정 모델이 로컬에 있는지 확인
  Future<bool> isDownloaded(String modelName) async {
    final dir = await modelPath(modelName);
    final marker = File(p.join(dir, '.ready'));
    return marker.existsSync();
  }

  /// 번역 경로에 필요한 모델이 모두 준비됐는지 확인
  Future<bool> isRouteReady(String src, String dst) async {
    final route = translationRoute(src, dst);
    for (final model in route) {
      if (!await isDownloaded(model)) return false;
    }
    return true;
  }

  /// 필요한 모델 다운로드 (없는 것만)
  Future<void> ensureModels(List<String> modelNames) async {
    for (final name in modelNames) {
      if (!await isDownloaded(name)) {
        await downloadModel(name);
      }
    }
  }

  /// 단일 모델 다운로드 + 압축 해제
  Future<void> downloadModel(String modelName) async {
    final dir = await modelDir;
    final destDir = Directory(p.join(dir, modelName));
    final zipPath = p.join(dir, '$modelName.zip');

    await destDir.create(recursive: true);

    final url = '${AppConfig.modelBaseUrl}/$modelName.zip';
    await _dio.download(
      url,
      zipPath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress?.call(modelName, received / total);
        }
      },
    );

    // ZIP 압축 해제 (Dart 기본 라이브러리 사용)
    await _extractZip(zipPath, destDir.path);

    // 정상 완료 마커
    await File(p.join(destDir.path, '.ready')).create();
    await File(zipPath).delete();
  }

  Future<void> _extractZip(String zipPath, String destDir) async {
    // Dart에는 내장 zip 라이브러리가 없으므로 플랫폼 명령 사용
    if (Platform.isAndroid || Platform.isLinux) {
      await Process.run('unzip', ['-o', zipPath, '-d', destDir]);
    } else if (Platform.isWindows) {
      await Process.run('powershell', [
        '-Command',
        'Expand-Archive',
        '-Path', zipPath,
        '-DestinationPath', destDir,
        '-Force',
      ]);
    } else if (Platform.isIOS || Platform.isMacOS) {
      await Process.run('unzip', ['-o', zipPath, '-d', destDir]);
    }
  }

  /// 다운로드된 모델 목록
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

  /// 총 캐시 크기 (MB)
  Future<double> totalCacheMb() async {
    final dir = Directory(await modelDir);
    if (!dir.existsSync()) return 0;
    int bytes = 0;
    await for (final f in dir.list(recursive: true)) {
      if (f is File) bytes += await f.length();
    }
    return bytes / 1024 / 1024;
  }

  /// 특정 모델 삭제
  Future<void> deleteModel(String modelName) async {
    final dir = Directory(await modelPath(modelName));
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
