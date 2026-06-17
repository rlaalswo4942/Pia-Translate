import 'package:flutter/material.dart';
import '../state/translate_notifier.dart';

/// 모델 다운로드 진행률 화면
class DownloadProgress extends StatelessWidget {
  final TranslateNotifier state;
  const DownloadProgress({super.key, required this.state});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            state.voiceState == VoiceState.downloadingModel
                ? Icons.record_voice_over_outlined
                : Icons.download_rounded,
            size: 56, color: const Color(0xFF1E2A3A),
          ),
          const SizedBox(height: 16),
          Text(
            state.voiceState == VoiceState.downloadingModel
                ? '음성 인식 모델 다운로드'
                : '번역 모델 다운로드',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            state.voiceState == VoiceState.downloadingModel
                ? '처음 한 번만 다운로드합니다 (약 370MB)'
                : '처음 한 번만 다운로드합니다\n(언어쌍당 약 60MB)',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
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
