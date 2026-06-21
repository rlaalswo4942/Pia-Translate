import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/config.dart';
import '../state/translate_notifier.dart';
import '../widgets/language_bar.dart';
import '../widgets/mic_button.dart';
import '../widgets/image_button.dart';
import '../widgets/recognized_card.dart';
import '../widgets/ocr_card.dart';
import '../widgets/result_card.dart';
import '../widgets/download_progress.dart';
import '../widgets/model_manager_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _inputCtrl = TextEditingController();
  final _notifier  = TranslateNotifier();

  @override
  void initState() {
    super.initState();
    // 첫 프레임 이후 전체 모델 다운로드 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifier.initAllModels();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: _notifier,
    child: Consumer<TranslateNotifier>(
      builder: (ctx, n, _) {
        // STT/OCR 결과 → 텍스트 필드 동기화
        n.onSttText = (text) {
          if (_inputCtrl.text != text) {
            _inputCtrl.text = text;
            _inputCtrl.selection =
                TextSelection.fromPosition(TextPosition(offset: text.length));
          }
        };

        // 초기 모델 다운로드 중이면 전용 설치 화면 표시
        if (n.isInitialSetup) {
          return _InitialSetupScreen(n: n);
        }

        final showDownload = n.voiceState == VoiceState.downloadingModel;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            title: const Text('Pia 번역',
                style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF1E2A3A),
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.storage_outlined),
                tooltip: '모델 관리',
                onPressed: () => showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => const ModelManagerSheet(),
                ),
              ),
            ],
          ),
          body: Column(children: [
            LanguageBar(state: n),
            Expanded(
              child: showDownload
                  ? DownloadProgress(state: n)
                  : _TranslateBody(n: n, inputCtrl: _inputCtrl),
            ),
          ]),
        );
      },
    ),
  );
}

// ── 초기 설치 화면 ────────────────────────────────────────────────────
class _InitialSetupScreen extends StatelessWidget {
  final TranslateNotifier n;
  const _InitialSetupScreen({required this.n});

  @override
  Widget build(BuildContext context) {
    final done    = n.setupModelDone;
    final total   = n.setupModelTotal;
    final failed  = n.setupFailedModels;
    final isRetrying = failed.isEmpty && n.downloadStatus.isNotEmpty;

    // 자동 재시도 중 (실패했지만 아직 20회 미만)
    if (failed.isNotEmpty && n.autoRetryRound <= 20 && n.downloadStatus.contains('재시도')) {
      return Scaffold(
        backgroundColor: const Color(0xFF1E2A3A),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF4FC3F7)),
                  const SizedBox(height: 32),
                  Text(n.downloadStatus,
                      style: const TextStyle(fontSize: 16, color: Colors.white70)),
                  const SizedBox(height: 8),
                  Text('${failed.length}개 모델 재시도 중...',
                      style: const TextStyle(fontSize: 13, color: Colors.white38)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 20회 모두 실패 → 수동 재시도 버튼 + 실제 에러 메시지 표시
    if (failed.isNotEmpty) {
      final errorLog = n.setupErrorLog;
      return Scaffold(
        backgroundColor: const Color(0xFF1E2A3A),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.cloud_off, size: 64, color: Color(0xFFEF9A9A)),
                const SizedBox(height: 20),
                const Text('다운로드 실패',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 8),
                Text(
                  '${failed.length}개 모델 / 자동 재시도 ${n.autoRetryRound}회 모두 실패',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.white60),
                ),
                const SizedBox(height: 20),
                // 모델별 에러 메시지 (진단용)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('오류 상세',
                          style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...failed.map((m) {
                        final err = errorLog[m] ?? '알 수 없는 오류';
                        // 긴 에러 메시지 80자로 자르기
                        final short = err.length > 80 ? '${err.substring(0, 80)}…' : err;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('[$m]',
                                  style: const TextStyle(
                                      color: Color(0xFFEF9A9A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                              Text(short,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // 전체 에러 로그 (복사용)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    failed.map((m) => '[$m]\n${errorLog[m] ?? ''}').join('\n\n'),
                    style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 10,
                        fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 4),
                const Text('위 텍스트를 길게 눌러 복사 후 개발자에게 전달하세요.',
                    style: TextStyle(color: Colors.white24, fontSize: 10)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => n.retryFailedModels(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('다시 시도'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4FC3F7),
                    foregroundColor: Colors.black87,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                // 실패한 모델 목록 (하단 요약)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: failed
                      .map((m) => Text('• $m',
                          style: const TextStyle(
                              color: Color(0xFFEF9A9A), fontSize: 13)))
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 다운로드 진행 중
    final progress = n.downloadProgress;
    final status   = n.downloadStatus;

    return Scaffold(
      backgroundColor: const Color(0xFF1E2A3A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.translate, size: 72, color: Colors.white70),
                const SizedBox(height: 24),
                const Text('Pia 번역',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 8),
                const Text(
                  '오프라인 번역 모델을 준비하고 있습니다.\n이후 인터넷 없이도 번역할 수 있습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.white60),
                ),
                const SizedBox(height: 48),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$done / $total 완료',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    Text('${(progress * 100).round()}%',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: total == 0
                        ? 0
                        : ((done - 1 + progress) / total).clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF4FC3F7)),
                  ),
                ),
                const SizedBox(height: 16),
                if (status.isNotEmpty)
                  Text(status,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 8),
                const Text(
                  'WiFi 연결 상태에서 약 3~5분 소요됩니다.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 번역 본문 (얇은 조립 레이어) ─────────────────────────────────────
class _TranslateBody extends StatelessWidget {
  final TranslateNotifier n;
  final TextEditingController inputCtrl;
  const _TranslateBody({required this.n, required this.inputCtrl});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [

      // ── 입력 카드 ────────────────────────────────────────────
      _card(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('${n.src.flag} ${n.src.name}',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const Spacer(),
            if (n.inputText.isNotEmpty && !n.isRecording)
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                color: Colors.grey,
                onPressed: () => n.clearAll(inputCtrl),
              ),
          ]),
          TextField(
            controller: inputCtrl,
            maxLines: null,
            minLines: 4,
            maxLength: AppConfig.maxInputChars,
            style: TextStyle(
                fontSize: 18,
                color:
                    n.isRecording ? Colors.grey.shade400 : Colors.black87),
            decoration: InputDecoration(
              hintText: n.isRecording
                  ? '듣는 중...'
                  : '${n.src.name}로 입력하세요...',
              border: InputBorder.none,
              counterStyle:
                  const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            enabled: !n.isRecording,
            onChanged: (v) {
              n.inputText = v;
              if (n.recognizedText.isNotEmpty) {
                n.recognizedText = '';
                n.notifyListeners();
              }
            },
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!n.isRecording)
                Text('${inputCtrl.text.length}자',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
              const Spacer(),
              ImageButton(state: n),
              const SizedBox(width: 4),
              MicButton(state: n),
              const SizedBox(width: 8),
              if (!n.isRecording && !n.isOcrRunning)
                ElevatedButton.icon(
                  onPressed: n.isTranslating
                      ? null
                      : () => n.runTranslation(context),
                  icon: n.isTranslating
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.translate, size: 18),
                  label: Text(n.isTranslating ? '번역 중...' : '번역'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E2A3A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ],
          ),
        ],
      )),

      const SizedBox(height: 12),

      // ── OCR 처리 중 ───────────────────────────────────────────
      if (n.isOcrRunning) ...[
        const OcrLoadingCard(),
        const SizedBox(height: 12),
      ],

      // ── OCR 결과 카드 ─────────────────────────────────────────
      if (n.ocrText.isNotEmpty && !n.isOcrRunning) ...[
        OcrCard(
          text: n.ocrText,
          imagePath: n.ocrImagePath,
          flag: n.src.flag,
          langName: n.src.name,
        ),
        const SizedBox(height: 12),
      ],

      // ── STT 결과 카드 ─────────────────────────────────────────
      if (n.recognizedText.isNotEmpty && n.ocrText.isEmpty) ...[
        RecognizedCard(
          text: n.recognizedText,
          flag: n.src.flag,
          langName: n.src.name,
        ),
        const SizedBox(height: 12),
      ],

      // ── 오류 메시지 ───────────────────────────────────────────
      if (n.errorMessage != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Text(n.errorMessage!,
              style:
                  TextStyle(color: Colors.red.shade800, fontSize: 13)),
        ),
        const SizedBox(height: 12),
      ],

      // ── 번역 결과 카드 ────────────────────────────────────────
      if (n.outputText.isNotEmpty)
        ResultCard(text: n.outputText, lang: n.dst),
    ],
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2))
      ],
    ),
    child: child,
  );
}
