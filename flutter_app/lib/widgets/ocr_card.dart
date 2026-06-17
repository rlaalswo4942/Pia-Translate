import 'dart:io';
import 'package:flutter/material.dart';

/// OCR 처리 중 표시
class OcrLoadingCard extends StatelessWidget {
  const OcrLoadingCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F5E9),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFA5D6A7)),
    ),
    child: const Row(children: [
      SizedBox(
        width: 20, height: 20,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: Color(0xFF2E7D32)),
      ),
      SizedBox(width: 12),
      Text('이미지 텍스트 인식 중...',
          style: TextStyle(color: Color(0xFF2E7D32))),
    ]),
  );
}

/// OCR 인식 결과 표시 — 초록 카드 (썸네일 포함)
class OcrCard extends StatelessWidget {
  final String text;
  final String imagePath;
  final String flag;
  final String langName;
  const OcrCard({
    super.key,
    required this.text,
    required this.imagePath,
    required this.flag,
    required this.langName,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F5E9),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFA5D6A7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.image_search_rounded,
              size: 15, color: Color(0xFF2E7D32)),
          const SizedBox(width: 6),
          Text('$flag $langName — 이미지 인식됨',
              style: const TextStyle(
                color: Color(0xFF2E7D32),
                fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imagePath.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(imagePath),
                  width: 72, height: 72, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            if (imagePath.isNotEmpty) const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 15, height: 1.5, color: Color(0xFF1A1A2E))),
            ),
          ],
        ),
      ],
    ),
  );
}
