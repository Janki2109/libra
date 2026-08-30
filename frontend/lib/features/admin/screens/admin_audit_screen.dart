import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';

class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});
  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  List<dynamic> _logs = [];
  bool _loading = true;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _page = 1;
        _hasMore = true;
        _logs = [];
      });
    }
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance
          .get('/admin/audit-logs?page=$_page&limit=30');
      final data = res.data['data'] ?? [];
      setState(() {
        _logs.addAll(data);
        _hasMore = data.length >= 30;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Color _actionColor(String action) {
    if (action.startsWith('create')) return AppColors.success;
    if (action.startsWith('update')) return AppColors.info;
    if (action.startsWith('delete')) return AppColors.error;
    if (action.startsWith('login')) return AppColors.gold;
    return AppColors.textMuted;
  }

  IconData _actionIcon(String action) {
    if (action.startsWith('create')) return Icons.add_circle_rounded;
    if (action.startsWith('update')) return Icons.edit_rounded;
    if (action.startsWith('delete')) return Icons.delete_rounded;
    if (action.startsWith('login')) return Icons.login_rounded;
    return Icons.info_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Audit Logs',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.gold),
            onPressed: () => _load(reset: true),
          ),
        ],
      ),
      body: _loading && _logs.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : _logs.isEmpty
              ? const Center(
                  child: Text('No audit logs',
                      style: TextStyle(color: AppColors.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _logs.length + (_hasMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _logs.length) {
                      return Center(
                        child: TextButton(
                          onPressed: () {
                            setState(() => _page++);
                            _load();
                          },
                          child: const Text('Load More',
                              style: TextStyle(color: AppColors.gold)),
                        ),
                      );
                    }
                    final log = _logs[i];
                    final action = (log['action'] ?? '').toString();
                    final color = _actionColor(action);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(_actionIcon(action),
                                color: color, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(action,
                                        style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12)),
                                  ),
                                  Text(_fmt(log['created_at'] ?? ''),
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 10)),
                                ]),
                                if ((log['user_name'] ?? '').isNotEmpty)
                                  Text('by ${log['user_name']}',
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 11)),
                                if ((log['entity_type'] ?? '').isNotEmpty)
                                  Text(
                                      '${log['entity_type']}${(log['entity_id'] ?? '').isNotEmpty ? ' #${(log['entity_id'] ?? '').toString().substring(0, 8)}' : ''}',
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 10)),
                              ],
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
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return s;
    }
  }
}
