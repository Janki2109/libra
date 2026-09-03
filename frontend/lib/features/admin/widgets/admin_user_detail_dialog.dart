import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';
import 'admin_shell.dart';
import 'admin_widgets.dart';

/// The shared "click a row → see the full profile" dialog for
/// Users/Lawyers/Students/Clients — all four are the same `users` table
/// underneath, so GET /admin/users/:id serves all four instead of needing
/// four different detail screens (see AdminGetUserDetail's doc comment).
Future<void> showAdminUserDetail(BuildContext context, String userId) async {
  showDialog(
    context: context,
    builder: (_) => _UserDetailDialog(userId: userId),
  );
}

class _UserDetailDialog extends StatefulWidget {
  final String userId;
  const _UserDetailDialog({required this.userId});
  @override
  State<_UserDetailDialog> createState() => _UserDetailDialogState();
}

class _UserDetailDialogState extends State<_UserDetailDialog> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _profile = {};
  List<dynamic> _asClient = [];
  List<dynamic> _asLawyer = [];
  List<dynamic> _documents = [];
  Map<String, dynamic>? _studentProgress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _repo.userDetail(widget.userId);
      final data = res['data'] as Map<String, dynamic>? ?? {};
      setState(() {
        _profile = (data['profile'] as Map<String, dynamic>?) ?? {};
        _asClient = (data['consultations_client'] as List?) ?? [];
        _asLawyer = (data['consultations_lawyer'] as List?) ?? [];
        _documents = (data['documents'] as List?) ?? [];
        _studentProgress = data['student_progress'] as Map<String, dynamic>?;
        _loading = false;
      });
    } on AdminException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 640),
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? SizedBox(height: 100, child: Center(child: Text(_error!)))
                : SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: kAdminAccent,
                          child: Text((_profile['name'] ?? '?').toString().substring(0, 1).toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_profile['name'] ?? '',
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kAdminTextPri)),
                            Text(_profile['email'] ?? '', style: const TextStyle(color: kAdminTextMuted, fontSize: 12)),
                          ]),
                        ),
                        AdminBadge((_profile['role_name'] ?? '').toString().replaceAll('_', ' '),
                            kAdminAccent),
                        const SizedBox(width: 8),
                        AdminBadge(_profile['is_active'] == true ? 'Active' : 'Suspended',
                            AdminBadge.colorFor(_profile['is_active'] == true ? 'active' : 'suspended')),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                      ]),
                      const Divider(height: 28),
                      Wrap(spacing: 24, runSpacing: 10, children: [
                        _field('Phone', _profile['phone']),
                        _field('Registered', fmtDate(_profile['created_at'])),
                        _field('Last login', fmtDate(_profile['last_login_at'])),
                        if ((_profile['designation'] ?? '').toString().isNotEmpty) _field('Designation', _profile['designation']),
                        if ((_profile['bar_council_number'] ?? '').toString().isNotEmpty)
                          _field('Bar Council No.', _profile['bar_council_number']),
                        if ((_profile['verification_status'] ?? '').toString().isNotEmpty)
                          _field('Verification', (_profile['verification_status']).toString()),
                      ]),
                      if (_asLawyer.isNotEmpty || (_profile['earnings_paid'] ?? 0) > 0 || (_profile['earnings_pending'] ?? 0) > 0) ...[
                        const SizedBox(height: 18),
                        Row(children: [
                          Expanded(child: _moneyTile('Earnings (Paid)', _profile['earnings_paid'], kAdminGreen)),
                          Expanded(child: _moneyTile('Earnings (Pending)', _profile['earnings_pending'], kAdminAmber)),
                        ]),
                      ],
                      if ((_profile['spent_total'] ?? 0) > 0) ...[
                        const SizedBox(height: 12),
                        _moneyTile('Total Spent', _profile['spent_total'], kAdminAccent),
                      ],
                      if (_studentProgress != null) ...[
                        const SizedBox(height: 18),
                        const Text('Student Activity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 20, runSpacing: 8, children: [
                          _field('Total Score', '${_studentProgress!['total_score']}'),
                          _field('Challenges', '${_studentProgress!['completed_challenges']}/${_studentProgress!['total_challenges']}'),
                          _field('Streak Days', '${_studentProgress!['streak_days']}'),
                        ]),
                      ],
                      if (_asLawyer.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('Consultations (as Lawyer)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        const SizedBox(height: 8),
                        ..._asLawyer.take(5).map(_consultRow),
                      ],
                      if (_asClient.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('Consultations (as Client)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        const SizedBox(height: 8),
                        ..._asClient.take(5).map(_consultRow),
                      ],
                      if (_documents.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('Documents', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        const SizedBox(height: 8),
                        ..._documents.map((d) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(children: [
                                const Icon(Icons.description_outlined, size: 15, color: kAdminTextMuted),
                                const SizedBox(width: 6),
                                Expanded(child: Text(d['file_name'] ?? '', style: const TextStyle(fontSize: 12.5))),
                                Text(fmtDate(d['created_at']), style: const TextStyle(fontSize: 11, color: kAdminTextMuted)),
                              ]),
                            )),
                      ],
                    ]),
                  ),
      ),
    );
  }

  Widget _field(String label, dynamic value) => SizedBox(
        width: 180,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: kAdminTextMuted, fontSize: 10.5)),
          Text((value ?? '—').toString().isEmpty ? '—' : value.toString(),
              style: const TextStyle(color: kAdminTextPri, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _moneyTile(String label, dynamic value, Color color) => Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fmtRupees(value as num?), style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: kAdminTextMuted, fontSize: 11)),
        ]),
      );

  Widget _consultRow(dynamic c) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: kAdminBg, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Expanded(
              child: Text('${c['consultation_type']} · ${c['client_name'] ?? c['lawyer_name'] ?? ''}',
                  style: const TextStyle(fontSize: 12.5))),
          Text(fmtDate(c['consultation_date']), style: const TextStyle(fontSize: 11, color: kAdminTextMuted)),
          const SizedBox(width: 8),
          AdminBadge(c['status'] ?? '', AdminBadge.colorFor(c['status'] ?? '')),
          const SizedBox(width: 6),
          AdminBadge(c['payment_status'] ?? '', AdminBadge.colorFor(c['payment_status'] ?? '')),
        ]),
      );
}
