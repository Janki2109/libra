import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

class AdminCasesScreen extends StatefulWidget {
  const AdminCasesScreen({super.key});
  @override
  State<AdminCasesScreen> createState() => _AdminCasesScreenState();
}

class _AdminCasesScreenState extends State<AdminCasesScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];
  bool _hasMore = false;
  int _page = 1;
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
      final res = await _repo.cases(search: _search, page: _page);
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
      activeRoute: '/admin/cases',
      title: 'Cases',
      actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      child: AdminSectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AdminSearchField(
              hint: 'Search case title or number…',
              onChanged: (v) {
                _search = v;
                _page = 1;
                _load();
              }),
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
                  DataColumn(label: Text('Case #')),
                  DataColumn(label: Text('Title')),
                  DataColumn(label: Text('Client')),
                  DataColumn(label: Text('Lawyer')),
                  DataColumn(label: Text('Court')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Next Hearing')),
                  DataColumn(label: Text('Created')),
                ],
                rows: _rows.map((c) {
                  return DataRow(cells: [
                    DataCell(Text((c['case_number'] ?? '').toString().isEmpty ? '—' : c['case_number'])),
                    DataCell(Text(c['case_title'] ?? '')),
                    DataCell(Text((c['client_name'] ?? '').toString().isEmpty ? '—' : c['client_name'])),
                    DataCell(Text((c['lawyer_name'] ?? '').toString().isEmpty ? '—' : c['lawyer_name'])),
                    DataCell(Text((c['court_name'] ?? '').toString().isEmpty ? '—' : c['court_name'])),
                    DataCell(AdminBadge(c['status'] ?? '', AdminBadge.colorFor(c['status'] ?? ''))),
                    DataCell(Text(c['next_hearing'] == null ? '—' : fmtDate(c['next_hearing']))),
                    DataCell(Text(fmtDate(c['created_at']))),
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
