import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/languages.dart';
import '../services/model_manager.dart';
import '../services/translator.dart' as tr;

// ── 상태 관리 ────────────────────────────────────────────────────
class TranslateState extends ChangeNotifier {
  Language _src = kSupportedLanguages[0]; // 한국어
  Language _dst = kSupportedLanguages[1]; // 영어

  Language get src => _src;
  Language get dst => _dst;

  String inputText  = '';
  String outputText = '';

  bool isTranslating = false;
  bool isDownloading = false;
  String downloadStatus = '';
  double downloadProgress = 0.0;
  String? errorMessage;

  void swapLanguages() {
    final tmp = _src;
    _src = _dst;
    _dst = tmp;
    final tmpText = inputText;
    inputText  = outputText;
    outputText = tmpText;
    notifyListeners();
  }

  void setSrc(Language l) {
    if (l.code == _dst.code) swapLanguages();
    else { _src = l; notifyListeners(); }
  }

  void setDst(Language l) {
    if (l.code == _src.code) swapLanguages();
    else { _dst = l; notifyListeners(); }
  }

  Future<void> runTranslation(BuildContext context) async {
    if (inputText.trim().isEmpty) return;

    final mm = ModelManager.instance;
    final route = translationRoute(_src.code, _dst.code);

    // 모델 준비 확인
    for (final model in route) {
      if (!await mm.isDownloaded(model)) {
        await _downloadModels(route, mm);
        break;
      }
    }

    isTranslating = true;
    errorMessage  = null;
    notifyListeners();

    try {
      outputText = await tr.translate(
        text:    inputText,
        srcLang: _src.code,
        dstLang: _dst.code,
      );
    } catch (e) {
      errorMessage = '번역 오류: $e';
      outputText   = '';
    } finally {
      isTranslating = false;
      notifyListeners();
    }
  }

  Future<void> _downloadModels(List<String> models, ModelManager mm) async {
    isDownloading = true;
    notifyListeners();

    mm.onProgress = (name, prog) {
      downloadStatus   = '$name 다운로드 중...';
      downloadProgress = prog;
      notifyListeners();
    };

    try {
      await mm.ensureModels(models);
    } catch (e) {
      errorMessage = '모델 다운로드 실패: $e\n\nconfig.dart의 modelBaseUrl을 확인하세요.';
      notifyListeners();
    } finally {
      isDownloading = false;
      mm.onProgress = null;
      notifyListeners();
    }
  }
}

// ── 메인 화면 ─────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TranslateState(),
      child: Consumer<TranslateState>(
        builder: (ctx, state, _) => Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: _buildAppBar(ctx, state),
          body: Column(
            children: [
              _LanguageBar(state: state),
              Expanded(
                child: state.isDownloading
                    ? _DownloadProgress(state: state)
                    : _TranslateBody(
                        state: state,
                        inputController: _inputController,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext ctx, TranslateState state) => AppBar(
    title: const Text('Pia 번역', style: TextStyle(fontWeight: FontWeight.bold)),
    backgroundColor: const Color(0xFF1E2A3A),
    foregroundColor: Colors.white,
    actions: [
      IconButton(
        icon: const Icon(Icons.storage_outlined),
        tooltip: '모델 관리',
        onPressed: () => _showModelManager(ctx),
      ),
    ],
  );

  void _showModelManager(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      builder: (_) => const _ModelManagerSheet(),
    );
  }
}

// ── 언어 선택 바 ──────────────────────────────────────────────────
class _LanguageBar extends StatelessWidget {
  final TranslateState state;
  const _LanguageBar({required this.state});

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF1E2A3A),
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    child: Row(
      children: [
        Expanded(child: _LangButton(lang: state.src, onTap: () => _pick(context, true))),
        IconButton(
          icon: const Icon(Icons.swap_horiz, color: Colors.white70, size: 28),
          onPressed: state.swapLanguages,
        ),
        Expanded(child: _LangButton(lang: state.dst, onTap: () => _pick(context, false))),
      ],
    ),
  );

  Future<void> _pick(BuildContext ctx, bool isSrc) async {
    final picked = await showDialog<Language>(
      context: ctx,
      builder: (_) => _LangPickerDialog(
        current: isSrc ? state.src : state.dst,
        exclude: isSrc ? state.dst.code : state.src.code,
      ),
    );
    if (picked != null) {
      isSrc ? state.setSrc(picked) : state.setDst(picked);
    }
  }
}

class _LangButton extends StatelessWidget {
  final Language lang;
  final VoidCallback onTap;
  const _LangButton({required this.lang, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(lang.flag, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(lang.name,
              style: const TextStyle(color: Colors.white, fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 20),
        ],
      ),
    ),
  );
}

class _LangPickerDialog extends StatelessWidget {
  final Language current;
  final String exclude;
  const _LangPickerDialog({required this.current, required this.exclude});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('언어 선택'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: kSupportedLanguages
          .where((l) => l.code != exclude)
          .map((l) => ListTile(
                leading: Text(l.flag, style: const TextStyle(fontSize: 24)),
                title: Text(l.name),
                subtitle: Text(l.nameEn),
                selected: l.code == current.code,
                onTap: () => Navigator.pop(context, l),
              ))
          .toList(),
    ),
  );
}

// ── 번역 본문 ─────────────────────────────────────────────────────
class _TranslateBody extends StatelessWidget {
  final TranslateState state;
  final TextEditingController inputController;
  const _TranslateBody({required this.state, required this.inputController});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // 입력 카드
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(state.src.flag + ' ' + state.src.name,
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const Spacer(),
                if (state.inputText.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    color: Colors.grey,
                    onPressed: () {
                      inputController.clear();
                      state.inputText  = '';
                      state.outputText = '';
                      state.errorMessage = null;
                      state.notifyListeners();
                    },
                  ),
              ],
            ),
            TextField(
              controller: inputController,
              maxLines: null,
              minLines: 4,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                hintText: '${state.src.name}로 입력하세요...',
                border: InputBorder.none,
              ),
              onChanged: (v) => state.inputText = v,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('${inputController.text.length}자',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: state.isTranslating
                      ? null
                      : () => state.runTranslation(context),
                  icon: state.isTranslating
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.translate, size: 18),
                  label: Text(state.isTranslating ? '번역 중...' : '번역'),
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
        ),
      ),

      const SizedBox(height: 12),

      // 오류 메시지
      if (state.errorMessage != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Text(state.errorMessage!,
              style: TextStyle(color: Colors.red.shade800, fontSize: 13)),
        ),

      // 번역 결과 카드
      if (state.outputText.isNotEmpty)
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(state.dst.flag + ' ' + state.dst.name,
                      style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    color: Colors.grey,
                    tooltip: '복사',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: state.outputText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('복사됨'), duration: Duration(seconds: 1)));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(
                state.outputText,
                style: const TextStyle(fontSize: 18, height: 1.5),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
          blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: child,
  );
}

// ── 다운로드 진행률 ───────────────────────────────────────────────
class _DownloadProgress extends StatelessWidget {
  final TranslateState state;
  const _DownloadProgress({required this.state});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.download_rounded, size: 56, color: Color(0xFF1E2A3A)),
          const SizedBox(height: 16),
          Text('번역 모델 다운로드',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('처음 한 번만 다운로드 합니다\n(언어쌍당 약 40~60MB)',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          LinearProgressIndicator(
            value: state.downloadProgress > 0 ? state.downloadProgress : null,
            backgroundColor: Colors.grey.shade200,
            color: const Color(0xFF1E2A3A),
          ),
          const SizedBox(height: 8),
          Text(state.downloadStatus,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    ),
  );
}

// ── 모델 관리 시트 ────────────────────────────────────────────────
class _ModelManagerSheet extends StatefulWidget {
  const _ModelManagerSheet();
  @override
  State<_ModelManagerSheet> createState() => _ModelManagerSheetState();
}

class _ModelManagerSheetState extends State<_ModelManagerSheet> {
  List<String> _downloaded = [];
  double _totalMb = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mm = ModelManager.instance;
    final models = await mm.downloadedModels();
    final mb     = await mm.totalCacheMb();
    setState(() { _downloaded = models; _totalMb = mb; });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('모델 관리',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${_totalMb.toStringAsFixed(0)}MB',
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 12),
        if (_downloaded.isEmpty)
          const Text('다운로드된 모델 없음', style: TextStyle(color: Colors.grey))
        else
          ..._downloaded.map((m) => ListTile(
            dense: true,
            leading: const Icon(Icons.check_circle, color: Colors.green, size: 20),
            title: Text(m.replaceAll('_', ' → ')),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () async {
                await ModelManager.instance.deleteModel(m);
                await _load();
              },
            ),
          )),
      ],
    ),
  );
}
