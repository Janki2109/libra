import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

class AdminHearingsScreen extends StatefulWidget {
  const AdminHearingsScreen({super.key});
  @override
  State<AdminHearingsScreen> createState() => _AdminHearingsScreenState();
}

class _AdminHearingsScreenState extends State<AdminHearingsScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];
  bool _hasMore = false;
  int _page = 1;
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
      final res = await _repo.hearings(status: _status, page: _page);
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

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/hearings',
      title: 'Courts / Hearings',
      actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      child: AdminSectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, children: [
            for (final s in const [
              ('', 'All'),
              ('scheduled', 'Scheduled'),
              ('completed', 'Completed'),
              ('adjourned', 'Adjourned'),
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
                  DataColumn(label: Text('Case')),
                  DataColumn(label: Text('Court')),
                  DataColumn(label: Text('Lawyer')),
                  DataColumn(label: Text('Client')),
                  DataColumn(label: Text('Hearing Date')),
                  DataColumn(label: Text('Time')),
                  DataColumn(label: Text('Status')),
                ],
                rows: _rows.map((h) {
                  return DataRow(cells: [
                    DataCell(Text((h['case_title'] ?? '').toString().isEmpty ? '—' : h['case_title'])),
                    DataCell(Text((h['court_name'] ?? '').toString().isEmpty ? '—' : h['court_name'])),
                    DataCell(Text((h['lawyer_name'] ?? '').toString().isEmpty ? '—' : h['lawyer_name'])),
                    DataCell(Text((h['client_name'] ?? '').toString().isEmpty ? '—' : h['client_name'])),
                    DataCell(Text(fmtDate(h['hearing_date']))),
                    DataCell(Text((h['hearing_time'] ?? '').toString().isEmpty ? '—' : h['hearing_time'])),
                    DataCell(AdminBadge(h['status'] ?? '', AdminBadge.colorFor(h['status'] ?? ''))),
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
    );
  }
}
