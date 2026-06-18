import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'services/data_collector.dart';

const _crashChannel = MethodChannel('com.pia.translate/crash');

void main() {
  FlutterError.onError = (details) {
    debugPrint('FlutterError: ${details.exception}\n${details.stack}');
  };

  runZonedGuarded(_boot, (error, stack) {
    debugPrint('Unhandled: $error\n$stack');
  });
}

Future<void> _boot() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 이전 실행에서 Java가 기록한 크래시 로그를 MethodChannel로 가져옴
  String? prevCrash;
  try {
    prevCrash = await _crashChannel.invokeMethod<String>('getCrashLog');
  } catch (_) {}

  try {
    await DataCollector.instance.init();
  } catch (e, st) {
    debugPrint('DataCollector init failed: $e\n$st');
    prevCrash ??= 'DataCollector: $e';
  }

  runApp(PiaTranslateApp(prevCrash: prevCrash));
}

class PiaTranslateApp extends StatelessWidget {
  final String? prevCrash;
  const PiaTranslateApp({super.key, this.prevCrash});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pia 번역',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme:
          ColorScheme.fromSeed(seedColor: const Color(0xFF1E2A3A)),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(elevation: 0, centerTitle: true),
    ),
    home: prevCrash != null
        ? _CrashScreen(crash: prevCrash!)
        : const _ConsentGate(),
  );
}

/// 이전 실행 크래시 내용 표시 화면
class _CrashScreen extends StatelessWidget {
  final String crash;
  const _CrashScreen({required this.crash});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('오류 정보')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('앱 시작 중 오류가 발생했습니다.',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('아래 내용을 복사해서 개발자에게 전달해주세요.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(crash,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: crash));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('클립보드에 복사됨')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('오류 내용 복사'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const _ConsentGate())),
                child: const Text('무시하고 계속'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentGate extends StatefulWidget {
  const _ConsentGate();
  @override
  State<_ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<_ConsentGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final dc = DataCollector.instance;
    if (dc.hasAnswered) {
      _goHome();
      return;
    }
    setState(() => _checked = true);
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pia 번역',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E2A3A))),
              const SizedBox(height: 8),
              const Text('완전 오프라인 다국어 번역 앱',
                  style: TextStyle(color: Colors.grey, fontSize: 15)),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 8)
                    ]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.school_outlined,
                          color: Color(0xFF1E2A3A), size: 22),
                      SizedBox(width: 8),
                      Text('Pia 학습 데이터 수집',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ]),
                    const SizedBox(height: 12),
                    const Text(
                      '이 앱을 사용하면서 발생하는 번역 기록을 익명으로 저장하여\n'
                      'Pia 음성 보조 AI의 학습 데이터로 활용할 수 있습니다.\n\n'
                      '• 수집 항목: 번역 원문, 번역 결과, 언어쌍\n'
                      '• 미수집 항목: 이름, 위치, 기기 ID 등 개인정보\n'
                      '• 언제든 설정에서 동의 철회 및 데이터 삭제 가능',
                      style: TextStyle(
                          color: Colors.black87,
                          fontSize: 13,
                          height: 1.6),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await DataCollector.instance.setConsent(true);
                    _goHome();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E2A3A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('동의하고 시작',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    await DataCollector.instance.setConsent(false);
                    _goHome();
                  },
                  child: const Text('동의 없이 시작',
                      style: TextStyle(color: Colors.grey)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
