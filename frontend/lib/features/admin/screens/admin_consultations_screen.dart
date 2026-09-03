import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

class AdminConsultationsScreen extends StatefulWidget {
  const AdminConsultationsScreen({super.key});
  @override
  State<AdminConsultationsScreen> createState() => _AdminConsultationsScreenState();
}

class _AdminConsultationsScreenState extends State<AdminConsultationsScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];
  bool _hasMore = false;
  int _page = 1;
  String _status = '';
  String _paymentStatus = '';
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
      final res = await _repo.consultations(status: _status, paymentStatus: _paymentStatus, search: _search, page: _page);
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

  void _showDetail(dynamic c) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text('${c['consultation_type']} Consultation',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              AdminBadge(c['status'] ?? '', AdminBadge.colorFor(c['status'] ?? '')),
              const SizedBox(width: 6),
              AdminBadge(c['payment_status'] ?? '', AdminBadge.colorFor(c['payment_status'] ?? '')),
            ]),
            const Divider(height: 24),
            _row('Client', '${c['client_name']} (${c['client_email']})'),
            _row('Lawyer', '${c['lawyer_name']} (${c['lawyer_email']})'),
            _row('Date / Time', '${fmtDate(c['consultation_date'])} · ${c['consultation_time']}'),
            _row('Amount', fmtRupees(c['amount_rupees'] as num?)),
            _row('Booked on', fmtDate(c['created_at'])),
          ]),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: kAdminTextMuted, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/consultations',
      title: 'Consultations',
      actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      child: AdminSectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            AdminSearchField(
                hint: 'Search client or lawyer…',
                onChanged: (v) {
                  _search = v;
                  _page = 1;
                  _load();
                }),
            for (final s in const [
              ('', 'All'),
              ('pending', 'Pending'),
              ('confirmed', 'Confirmed'),
              ('completed', 'Completed'),
              ('cancelled', 'Cancelled'),
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
          const SizedBox(height: 8),
          Wrap(spacing: 10, children: [
            for (final s in const [
              ('', 'Any payment'),
              ('paid', 'Payment Successful'),
              ('pending', 'Payment Pending'),
              ('failed', 'Payment Failed'),
            ])
              AdminFilterChip(
                  label: s.$2,
                  selected: _paymentStatus == s.$1,
                  onTap: () {
                    setState(() {
                      _paymentStatus = s.$1;
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
                  DataColumn(label: Text('Client')),
                  DataColumn(label: Text('Lawyer')),
                  DataColumn(label: Text('Type')),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Time')),
                  DataColumn(label: Text('Price')),
                  DataColumn(label: Text('Payment')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Booked')),
                ],
                rows: _rows.map((c) {
                  return DataRow(
                    onSelectChanged: (_) => _showDetail(c),
                    cells: [
                      DataCell(Text(c['client_name'] ?? '')),
                      DataCell(Text(c['lawyer_name'] ?? '')),
                      DataCell(Text(c['consultation_type'] ?? '')),
                      DataCell(Text(fmtDate(c['consultation_date']))),
                      DataCell(Text(c['consultation_time'] ?? '')),
                      DataCell(Text(fmtRupees(c['amount_rupees'] as num?))),
                      DataCell(AdminBadge(c['payment_status'] ?? '', AdminBadge.colorFor(c['payment_status'] ?? ''))),
                      DataCell(AdminBadge(c['status'] ?? '', AdminBadge.colorFor(c['status'] ?? ''))),
                      DataCell(Text(fmtDate(c['created_at']))),
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
