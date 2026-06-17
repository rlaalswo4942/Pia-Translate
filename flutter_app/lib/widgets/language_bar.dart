import 'package:flutter/material.dart';
import '../core/languages.dart';
import '../state/translate_notifier.dart';

class LanguageBar extends StatelessWidget {
  final TranslateNotifier state;
  const LanguageBar({super.key, required this.state});

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF1E2A3A),
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    child: Row(
      children: [
        Expanded(child: LangButton(lang: state.src, onTap: () => _pick(context, true))),
        IconButton(
          icon: const Icon(Icons.swap_horiz, color: Colors.white70, size: 28),
          onPressed: state.swapLanguages,
        ),
        Expanded(child: LangButton(lang: state.dst, onTap: () => _pick(context, false))),
      ],
    ),
  );

  Future<void> _pick(BuildContext ctx, bool isSrc) async {
    final picked = await showDialog<Language>(
      context: ctx,
      builder: (_) => LangPickerDialog(
        current: isSrc ? state.src : state.dst,
        exclude: isSrc ? state.dst.code : state.src.code,
      ),
    );
    if (picked != null) isSrc ? state.setSrc(picked) : state.setDst(picked);
  }
}

class LangButton extends StatelessWidget {
  final Language lang;
  final VoidCallback onTap;
  const LangButton({super.key, required this.lang, required this.onTap});

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
              style: const TextStyle(color: Colors.white,
                  fontSize: 15, fontWeight: FontWeight.w600)),
          const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 20),
        ],
      ),
    ),
  );
}

class LangPickerDialog extends StatelessWidget {
  final Language current;
  final String exclude;
  const LangPickerDialog({super.key, required this.current, required this.exclude});

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
