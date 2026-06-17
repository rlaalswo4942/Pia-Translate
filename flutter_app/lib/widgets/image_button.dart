import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../state/translate_notifier.dart';

class ImageButton extends StatelessWidget {
  final TranslateNotifier state;
  const ImageButton({super.key, required this.state});

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF2E7D32),
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: state.isBusy ? null : () => _showPicker(context),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: state.isOcrRunning
            ? const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.image_search_rounded, color: Colors.white, size: 24),
      ),
    ),
  );

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('이미지 선택',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: Color(0xFF2E7D32)),
              title: const Text('카메라로 촬영'),
              onTap: () {
                Navigator.pop(context);
                state.pickAndOcr(context, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Color(0xFF2E7D32)),
              title: const Text('갤러리에서 선택'),
              onTap: () {
                Navigator.pop(context);
                state.pickAndOcr(context, ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
