import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';

class CaseTimelineScreen extends StatefulWidget {
  final String caseId;
  const CaseTimelineScreen({super.key, required this.caseId});
  @override
  State<CaseTimelineScreen> createState() => _CaseTimelineScreenState();
}

class _CaseTimelineScreenState extends State<CaseTimelineScreen> {
  List<dynamic> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await DioClient.instance
          .get('/cases/${widget.caseId}/timeline');
      setState(() {
        _events = res.data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'case_filed': return Icons.gavel_rounded;
      case 'hearing': return Icons.event_rounded;
      case 'document_upload': return Icons.upload_file_rounded;
      case 'status_change': return Icons.sync_rounded;
      default: return Icons.circle_rounded;
    }
  }

  Color _color(String type) {
    switch (type) {
      case 'case_filed': return AppColors.gold;
      case 'hearing': return AppColors.info;
      case 'document_upload': return AppColors.success;
      case 'status_change': return AppColors.warning;
      default: return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Case Timeline',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : _events.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timeline_rounded,
                          color: AppColors.textMuted, size: 64),
                      SizedBox(height: 16),
                      Text('No Timeline Events',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 16)),
                      SizedBox(height: 8),
                      Text('Events appear as the case progresses.',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _events.length,
                  itemBuilder: (_, i) {
                    final e = _events[i];
                    final type = e['event_type'] ?? '';
                    final color = _color(type);
                    final isLast = i == _events.length - 1;
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(color: color, width: 2),
                              ),
                              child: Icon(_icon(type), color: color, size: 16),
                            ),
                            if (!isLast)
                              Expanded(
                                child: Container(
                                    width: 2,
                                    color: AppColors.border),
                              ),
                          ]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              margin:
                                  EdgeInsets.only(bottom: isLast ? 0 : 16),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.bgCard,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e['title'] ?? '',
                                      style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  if ((e['description'] ?? '').isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(e['description'],
                                        style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 11)),
                                  ],
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    const Icon(Icons.access_time_rounded,
                                        color: AppColors.textMuted, size: 12),
                                    const SizedBox(width: 4),
                                    Text(_fmt(e['event_date'] ?? ''),
                                        style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 11)),
                                  ]),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  String _fmt(String s) {
    try {
      final dt = DateTime.parse(s).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return s;
    }
  }
}
