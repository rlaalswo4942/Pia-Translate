import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/languages.dart';
import '../services/tts_service.dart';

/// 번역 결과 카드 — 복사 + TTS 버튼 포함
class ResultCard extends StatelessWidget {
  final String text;
  final Language lang;
  const ResultCard({super.key, required this.text, required this.lang});

  @override
  Widget build(BuildContext context) => Container(
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('${lang.flag} ${lang.name}',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const Spacer(),
          if (TtsService.instance.isAvailable)
            IconButton(
              icon: const Icon(Icons.volume_up_outlined, size: 20),
              color: const Color(0xFF1E2A3A),
              tooltip: '읽어주기',
              onPressed: () =>
                  TtsService.instance.speak(text, lang.code),
            ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            color: Colors.grey,
            tooltip: '복사',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('복사됨'),
                    duration: Duration(seconds: 1)));
            },
          ),
        ]),
        const SizedBox(height: 4),
        SelectableText(
          text,
          style: const TextStyle(fontSize: 18, height: 1.5),
        ),
      ],
    ),
  );
}
