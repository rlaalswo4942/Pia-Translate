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

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => TranslateNotifier(),
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

        final showDownload =
            n.isDownloading || n.voiceState == VoiceState.downloadingModel;

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
