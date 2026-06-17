import 'package:flutter/material.dart';

/// STT 인식 결과 표시 — 파란 카드
class RecognizedCard extends StatelessWidget {
  final String text;
  final String flag;
  final String langName;
  const RecognizedCard({
    super.key,
    required this.text,
    required this.flag,
    required this.langName,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F4FD),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFB3D9F5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.mic, size: 15, color: Color(0xFF1976D2)),
          const SizedBox(width: 6),
          Text('$flag $langName — 인식됨',
              style: const TextStyle(
                color: Color(0xFF1976D2),
                fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Text(text,
            style: const TextStyle(
                fontSize: 17, height: 1.5, color: Color(0xFF1A1A2E))),
      ],
    ),
  );
}
