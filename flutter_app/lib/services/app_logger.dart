import 'package:flutter/material.dart';

/// 앱 전역 로그 — UI에서 AnimatedBuilder로 실시간 감지 가능
class AppLogger extends ChangeNotifier {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const _maxLines = 500;
  final List<String> _logs = [];

  void log(String tag, String msg) {
    final t  = DateTime.now();
    final ts = '${_p(t.hour)}:${_p(t.minute)}:${_p(t.second)}.${(t.millisecond ~/ 10).toString().padLeft(2, '0')}';
    _logs.add('[$ts][$tag] $msg');
    if (_logs.length > _maxLines) _logs.removeRange(0, _logs.length - _maxLines);
    notifyListeners();
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  List<String> get logs => List.unmodifiable(_logs);
  String get full       => _logs.join('\n');
  void   clear()        { _logs.clear(); notifyListeners(); }
}
