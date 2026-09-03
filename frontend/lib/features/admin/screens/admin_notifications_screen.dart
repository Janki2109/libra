import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

/// Admin → Notifications. Reuses utils.Notify (in-app row + FCM push if
/// configured) for the "notify a role/user" controls — see
/// AdminSendNotification's doc comment. No second push pipeline.
class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});
  @override
  State<AdminNotificationsScreen> createState() => _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];
  bool _hasMore = false;
  int _page = 1;

  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _target = 'lawyers';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _repo.notifications(page: _page);
      setState(() {
        _rows = (res['data'] as List?) ?? [];
        _hasMore = (res['meta']?['has_more'] as bool?) ?? false;
        _loading = false;
      });
    } on AdminException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _send() async {
    if (_titleCtrl.text.trim().isEmpty || _messageCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      final count = await _repo.sendNotification(target: _target, title: _titleCtrl.text.trim(), message: _messageCtrl.text.trim());
      _titleCtrl.clear();
      _messageCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sent to $count recipient(s).')));
      }
      _load();
    } on AdminException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/notifications',
      title: 'Notifications',
      actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AdminSectionCard(
          title: 'Send Notification',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              for (final t in const [
                ('lawyers', 'All Lawyers'),
                ('students', 'All Students'),
                ('clients', 'All Clients'),
              ])
                AdminFilterChip(label: t.$2, selected: _target == t.$1, onTap: () => setState(() => _target = t.$1)),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _messageCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 16, color: Colors.white),
              label: const Text('Send', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: kAdminAccent),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        AdminSectionCard(
          title: 'Recent Notifications',
          child: Column(children: [
            if (_loading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              AdminEmptyState(message: _error!)
            else if (_rows.isEmpty)
              const AdminEmptyState()
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(kAdminBg),
                  columns: const [
                    DataColumn(label: Text('Recipient')),
                    DataColumn(label: Text('Role')),
                    DataColumn(label: Text('Title')),
                    DataColumn(label: Text('Message')),
                    DataColumn(label: Text('Type')),
                    DataColumn(label: Text('Read')),
                    DataColumn(label: Text('Sent')),
                  ],
                  rows: _rows.map((n) {
                    return DataRow(cells: [
                      DataCell(Text(n['user_name'] ?? '')),
                      DataCell(AdminBadge((n['user_role'] ?? '').toString().replaceAll('_', ' '), kAdminAccent)),
                      DataCell(Text(n['title'] ?? '')),
                      DataCell(SizedBox(width: 260, child: Text(n['message'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis))),
                      DataCell(Text(n['type'] ?? '', style: const TextStyle(color: kAdminTextMuted, fontSize: 11.5))),
                      DataCell(Icon(n['is_read'] == true ? Icons.mark_email_read_rounded : Icons.mark_email_unread_rounded,
                          size: 16, color: n['is_read'] == true ? kAdminGreen : kAdminAmber)),
                      DataCell(Text(fmtDate(n['created_at']))),
                    ]);
                  }).toList(),
                ),
              ),
            AdminPager(page: _page, hasMore: _hasMore, loading: _loading, onPageChange: (p) {
              setState(() => _page = p);
              _load();
            }),
          ]),
        ),
      ]),
    );
  }
}
