import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/data_collector.dart';
import '../services/model_manager.dart';

/// 모델 관리 + Pia 학습 데이터 수집 설정 시트
class ModelManagerSheet extends StatefulWidget {
  const ModelManagerSheet({super.key});
  @override
  State<ModelManagerSheet> createState() => _ModelManagerSheetState();
}

class _ModelManagerSheetState extends State<ModelManagerSheet> {
  List<String> _downloaded = [];
  double _totalMb   = 0;
  int    _dataCount = 0;
  bool   _consent   = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mm      = ModelManager.instance;
    final dc      = DataCollector.instance;
    final models  = await mm.downloadedModels();
    final mb      = await mm.totalCacheMb();
    final count   = await dc.recordCount();
    setState(() {
      _downloaded = models;
      _totalMb    = mb;
      _dataCount  = count;
      _consent    = dc.consentGiven;
    });
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: 0.6,
    minChildSize: 0.4,
    maxChildSize: 0.9,
    expand: false,
    builder: (_, ctrl) => ListView(
      controller: ctrl,
      padding: const EdgeInsets.all(20),
      children: [
        // ── 핸들 ─────────────────────────────────────────────
        Center(
          child: Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),

        // ── 번역 모델 ─────────────────────────────────────────
        Row(children: [
          const Text('번역 모델',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('${_totalMb.toStringAsFixed(0)}MB',
              style: const TextStyle(color: Colors.grey)),
        ]),
        const SizedBox(height: 12),
        if (_downloaded.isEmpty)
          const Text('다운로드된 모델 없음',
              style: TextStyle(color: Colors.grey))
        else
          ..._downloaded.map((m) => ListTile(
            dense: true,
            leading: Icon(
              m == 'vosk_ko'
                  ? Icons.record_voice_over
                  : Icons.translate,
              color: Colors.green, size: 20,
            ),
            title: Text(m == 'vosk_ko'
                ? '음성 인식 (한국어)'
                : m.replaceAll('_', ' → ')),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () async {
                await ModelManager.instance.deleteModel(m);
                await _load();
              },
            ),
          )),

        const Divider(height: 32),

        // ── Pia 학습 데이터 수집 ──────────────────────────────
        const Text('Pia 학습 데이터',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          '번역 기록을 익명으로 저장하여 Pia 음성 보조 AI 학습에 사용합니다.\n'
          '개인정보(위치, 기기 ID 등)는 일절 수집하지 않습니다.',
          style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('데이터 수집 동의'),
          subtitle: Text('누적 기록: $_dataCount건'),
          value: _consent,
          activeColor: const Color(0xFF1E2A3A),
          onChanged: (v) async {
            await DataCollector.instance.setConsent(v);
            await _load();
          },
        ),
        if (_consent && _dataCount > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('JSONL 내보내기'),
                onPressed: _export,
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18,
                  color: Colors.red),
              label: const Text('삭제',
                  style: TextStyle(color: Colors.red)),
              onPressed: _confirmDelete,
            ),
          ]),
        ],
      ],
    ),
  );

  Future<void> _export() async {
    final path = await DataCollector.instance.exportJsonl();
    if (path == null || !mounted) return;
    await Share.shareXFiles(
      [XFile(path)],
      subject: 'Pia 학습 데이터',
      text: '번역 기록 JSONL — Pia AI 학습용',
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('데이터 삭제'),
        content: Text('수집된 $_dataCount건의 번역 기록을 삭제합니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DataCollector.instance.deleteAll();
      await _load();
    }
  }
}
