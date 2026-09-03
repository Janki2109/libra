import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_user_detail_dialog.dart';
import '../widgets/admin_widgets.dart';

/// Reuses GET /admin/lawyers (already carries earnings_paid/earnings_pending
/// per lawyer) rather than a second earnings-specific endpoint — see that
/// handler's aggregate subqueries in admin_controller.go. Clicking a row
/// opens the same user-detail dialog Users/Lawyers/Students/Clients all
/// share, whose consultations-as-lawyer list is the detailed earning
/// history this section's spec asks for.
class AdminLawyerEarningsScreen extends StatefulWidget {
  const AdminLawyerEarningsScreen({super.key});
  @override
  State<AdminLawyerEarningsScreen> createState() => _AdminLawyerEarningsScreenState();
}

class _AdminLawyerEarningsScreenState extends State<AdminLawyerEarningsScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];

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
      final res = await _repo.lawyers();
      final rows = List<dynamic>.from((res['data'] as List?) ?? []);
      rows.sort((a, b) =>
          (((b['earnings_paid'] as num?) ?? 0) + ((b['earnings_pending'] as num?) ?? 0))
              .compareTo(((a['earnings_paid'] as num?) ?? 0) + ((a['earnings_pending'] as num?) ?? 0)));
      setState(() {
        _rows = rows;
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
    final totalPaid = _rows.fold<double>(0, (s, r) => s + ((r['earnings_paid'] as num?) ?? 0));
    final totalPending = _rows.fold<double>(0, (s, r) => s + ((r['earnings_pending'] as num?) ?? 0));

    return AdminShell(
      activeRoute: '/admin/lawyer-earnings',
      title: 'Lawyer Earnings',
      actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      child: _loading
          ? const Padding(padding: EdgeInsets.only(top: 100), child: Center(child: CircularProgressIndicator()))
          : _error != null
              ? AdminEmptyState(message: _error!)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: AdminStatCard(label: 'Total Paid Out (ledger)', value: fmtRupees(totalPaid), icon: Icons.check_circle_rounded, color: kAdminGreen)),
                    const SizedBox(width: 12),
                    Expanded(child: AdminStatCard(label: 'Total Pending', value: fmtRupees(totalPending), icon: Icons.hourglass_top_rounded, color: kAdminAmber)),
                    const SizedBox(width: 12),
                    Expanded(child: AdminStatCard(label: 'Lawyers with Earnings', value: '${_rows.where((r) => ((r['earnings_paid'] as num?) ?? 0) > 0).length}', icon: Icons.gavel_rounded, color: kAdminAccent)),
                  ]),
                  const SizedBox(height: 20),
                  AdminSectionCard(
                    title: 'Per-Lawyer Earnings',
                    child: _rows.isEmpty
                        ? const AdminEmptyState()
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(kAdminBg),
                              columns: const [
                                DataColumn(label: Text('Lawyer')),
                                DataColumn(label: Text('Consultations')),
                                DataColumn(label: Text('Completed')),
                                DataColumn(label: Text('Earnings Paid')),
                                DataColumn(label: Text('Earnings Pending')),
                                DataColumn(label: Text('Total')),
                              ],
                              rows: _rows.map((l) {
                                final paid = (l['earnings_paid'] as num?) ?? 0;
                                final pending = (l['earnings_pending'] as num?) ?? 0;
                                return DataRow(
                                  onSelectChanged: (_) => showAdminUserDetail(context, l['id']),
                                  cells: [
                                    DataCell(Text(l['name'] ?? '')),
                                    DataCell(Text('${l['total_consultations'] ?? 0}')),
                                    DataCell(Text('${l['completed_consultations'] ?? 0}')),
                                    DataCell(Text(fmtRupees(paid), style: const TextStyle(color: kAdminGreen, fontWeight: FontWeight.w700))),
                                    DataCell(Text(fmtRupees(pending), style: const TextStyle(color: kAdminAmber))),
                                    DataCell(Text(fmtRupees(paid + pending), style: const TextStyle(fontWeight: FontWeight.w800))),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                  ),
                ]),
    );
  }
}
