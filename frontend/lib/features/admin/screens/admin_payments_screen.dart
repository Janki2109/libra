import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

/// Payment Management + Razorpay Payment Details in one screen — both read
/// from the same payment_orders table (see AdminGetPayments' doc comment),
/// so there is one list, not two.
class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});
  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];
  bool _hasMore = false;
  int _page = 1;
  String _status = '';
  String _search = '';

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
      final res = await _repo.payments(status: _status, search: _search, page: _page);
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

  void _showDetail(dynamic p) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Payment Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
            Row(children: [
              AdminBadge(p['kind'] ?? '', kAdminAccent),
              const SizedBox(width: 6),
              AdminBadge(p['status'] ?? '', AdminBadge.colorFor(p['status'] ?? '')),
            ]),
            const Divider(height: 24),
            _row('Razorpay Order ID', p['order_id'] ?? '—'),
            _row('Razorpay Payment ID', (p['payment_id'] ?? '').toString().isEmpty ? '—' : p['payment_id']),
            _row('Amount', '${fmtRupees(p['amount_rupees'] as num?)} ${p['currency'] ?? ''}'),
            _row('User', '${p['user_name']} (${p['user_role']})'),
            if ((p['lawyer_name'] ?? '').toString().isNotEmpty) _row('Lawyer', p['lawyer_name']),
            _row('Created', fmtDate(p['created_at'])),
            _row('Last Updated', fmtDate(p['updated_at'])),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: kAdminBg, borderRadius: BorderRadius.circular(8)),
              child: const Row(children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: kAdminTextMuted),
                SizedBox(width: 6),
                Expanded(
                    child: Text('Razorpay secret keys are never shown here — they stay server-side only.',
                        style: TextStyle(fontSize: 11, color: kAdminTextMuted))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(color: kAdminTextMuted, fontSize: 12))),
          Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/payments',
      title: 'Payments',
      actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      child: AdminSectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            AdminSearchField(
                hint: 'Order ID, payment ID, name, email…',
                onChanged: (v) {
                  _search = v;
                  _page = 1;
                  _load();
                }),
            for (final s in const [
              ('', 'All'),
              ('paid', 'Successful'),
              ('created', 'Pending'),
              ('failed', 'Failed'),
            ])
              AdminFilterChip(
                  label: s.$2,
                  selected: _status == s.$1,
                  onTap: () {
                    setState(() {
                      _status = s.$1;
                      _page = 1;
                    });
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
                  DataColumn(label: Text('Order ID')),
                  DataColumn(label: Text('Payment ID')),
                  DataColumn(label: Text('User')),
                  DataColumn(label: Text('Role')),
                  DataColumn(label: Text('Kind')),
                  DataColumn(label: Text('Amount')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Date')),
                ],
                rows: _rows.map((p) {
                  return DataRow(
                    onSelectChanged: (_) => _showDetail(p),
                    cells: [
                      DataCell(Text(p['order_id'] ?? '', style: const TextStyle(fontSize: 11.5))),
                      DataCell(Text((p['payment_id'] ?? '').toString().isEmpty ? '—' : p['payment_id'], style: const TextStyle(fontSize: 11.5))),
                      DataCell(Text(p['user_name'] ?? '')),
                      DataCell(Text(p['user_role'] ?? '', style: const TextStyle(color: kAdminTextMuted))),
                      DataCell(AdminBadge(p['kind'] ?? '', kAdminAccent)),
                      DataCell(Text(fmtRupees(p['amount_rupees'] as num?))),
                      DataCell(AdminBadge(p['status'] ?? '', AdminBadge.colorFor(p['status'] ?? ''))),
                      DataCell(Text(fmtDate(p['created_at']))),
                    ],
                  );
                }).toList(),
              ),
            ),
          AdminPager(page: _page, hasMore: _hasMore, loading: _loading, onPageChange: (p) {
            setState(() => _page = p);
            _load();
          }),
        ]),
      ),
    );
  }
}
