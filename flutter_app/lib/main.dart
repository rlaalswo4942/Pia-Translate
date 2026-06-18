import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/data_collector.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PiaTranslateApp());
}

class PiaTranslateApp extends StatelessWidget {
  const PiaTranslateApp({super.key});

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
        home: const _AppLoader(),
      );
}

/// 앱 시작 화면 — DataCollector 초기화 후 적절한 화면으로 이동
class _AppLoader extends StatefulWidget {
  const _AppLoader();

  @override
  State<_AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<_AppLoader> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await DataCollector.instance.init();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DataCollector.instance.hasAnswered
            ? const HomeScreen()
            : const _ConsentGate(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}

class _ConsentGate extends StatelessWidget {
  const _ConsentGate();

  @override
  Widget build(BuildContext context) {
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
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.school_outlined,
                          color: Color(0xFF1E2A3A), size: 22),
                      SizedBox(width: 8),
                      Text('Pia 학습 데이터 수집',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ]),
                    SizedBox(height: 12),
                    Text(
                      '이 앱을 사용하면서 발생하는 번역 기록을 익명으로 저장하여\n'
                      'Pia 음성 보조 AI의 학습 데이터로 활용할 수 있습니다.\n\n'
                      '• 수집 항목: 번역 원문, 번역 결과, 언어쌍\n'
                      '• 미수집 항목: 이름, 위치, 기기 ID 등 개인정보\n'
                      '• 언제든 설정에서 동의 철회 및 데이터 삭제 가능',
                      style: TextStyle(
                          color: Colors.black87, fontSize: 13, height: 1.6),
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
                    if (!context.mounted) return;
                    Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const HomeScreen()));
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
                    if (!context.mounted) return;
                    Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const HomeScreen()));
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
