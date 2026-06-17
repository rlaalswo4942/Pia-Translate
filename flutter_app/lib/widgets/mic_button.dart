import 'package:flutter/material.dart';
import '../state/translate_notifier.dart';

class MicButton extends StatefulWidget {
  final TranslateNotifier state;
  const MicButton({super.key, required this.state});
  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recording = widget.state.isRecording;
    final busy      = widget.state.isTranslating || widget.state.isDownloading;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Transform.scale(
        scale: recording ? (1.0 + _pulse.value * 0.12) : 1.0,
        child: Material(
          color: recording ? Colors.red : const Color(0xFF1E2A3A),
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: busy ? null : () => widget.state.toggleRecording(context),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                recording ? Icons.stop_rounded : Icons.mic_none_rounded,
                color: Colors.white, size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
