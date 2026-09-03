import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_user_detail_dialog.dart';
import '../widgets/admin_widgets.dart';

class AdminLawyersScreen extends StatefulWidget {
  const AdminLawyersScreen({super.key});
  @override
  State<AdminLawyersScreen> createState() => _AdminLawyersScreenState();
}

class _AdminLawyersScreenState extends State<AdminLawyersScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];
  String _status = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _repo.lawyers(status: _status);
      setState(() {
        _rows = (res['data'] as List?) ?? [];
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
    return AdminShell(
      activeRoute: '/admin/lawyers',
      title: 'Lawyers',
      actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      child: AdminSectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, children: [
            for (final s in const [
              ('', 'All'),
              ('verified', 'Verified'),
              ('pending', 'Pending Verification'),
              ('rejected', 'Rejected'),
            ])
              AdminFilterChip(
                  label: s.$2,
                  selected: _status == s.$1,
                  onTap: () {
                    setState(() => _status = s.$1);
                    _load();
                  }),
          ]),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator()))
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
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Bar Council No.')),
                  DataColumn(label: Text('Verification')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Clients')),
                  DataColumn(label: Text('Consultations')),
                  DataColumn(label: Text('Completed')),
                  DataColumn(label: Text('Cancelled')),
                  DataColumn(label: Text('Earnings (Paid)')),
                  DataColumn(label: Text('Earnings (Pending)')),
                  DataColumn(label: Text('Registered')),
                ],
                rows: _rows.map((l) {
                  final active = l['is_active'] == true;
                  return DataRow(cells: [
                    DataCell(Text(l['name'] ?? ''), onTap: () => showAdminUserDetail(context, l['id'])),
                    DataCell(Text(l['email'] ?? '', style: const TextStyle(color: kAdminTextMuted))),
                    DataCell(Text((l['bar_council_number'] ?? '').toString().isEmpty ? '—' : l['bar_council_number'])),
                    DataCell(AdminBadge(l['verification_status'] ?? '', AdminBadge.colorFor(l['verification_status'] ?? ''))),
                    DataCell(AdminBadge(active ? 'Active' : 'Suspended', AdminBadge.colorFor(active ? 'active' : 'suspended'))),
                    DataCell(Text('${l['total_clients'] ?? 0}')),
                    DataCell(Text('${l['total_consultations'] ?? 0}')),
                    DataCell(Text('${l['completed_consultations'] ?? 0}')),
                    DataCell(Text('${l['cancelled_consultations'] ?? 0}')),
                    DataCell(Text(fmtRupees(l['earnings_paid'] as num?), style: const TextStyle(color: kAdminGreen, fontWeight: FontWeight.w700))),
                    DataCell(Text(fmtRupees(l['earnings_pending'] as num?), style: const TextStyle(color: kAdminAmber))),
                    DataCell(Text(fmtDate(l['created_at']))),
                  ]);
                }).toList(),
              ),
            ),
        ]),
      ),
    );
  }
}
