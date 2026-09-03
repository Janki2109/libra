import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

class AdminDocumentsScreen extends StatefulWidget {
  const AdminDocumentsScreen({super.key});
  @override
  State<AdminDocumentsScreen> createState() => _AdminDocumentsScreenState();
}

class _AdminDocumentsScreenState extends State<AdminDocumentsScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];
  bool _hasMore = false;
  int _page = 1;
  String _ownerRole = '';

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
      final res = await _repo.documents(ownerRole: _ownerRole, page: _page);
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
      activeRoute: '/admin/documents',
      title: 'Documents',
      actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      child: AdminSectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, children: [
            for (final r in const [
              ('', 'All Owners'),
              ('lawyer', 'Lawyer Documents'),
              ('client', 'Client Documents'),
              ('law_student', 'Student Documents'),
            ])
              AdminFilterChip(
                  label: r.$2,
                  selected: _ownerRole == r.$1,
                  onTap: () {
                    setState(() {
                      _ownerRole = r.$1;
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
                  DataColumn(label: Text('File Name')),
                  DataColumn(label: Text('Type')),
                  DataColumn(label: Text('Category')),
                  DataColumn(label: Text('Owner')),
                  DataColumn(label: Text('Owner Role')),
                  DataColumn(label: Text('Verification')),
                  DataColumn(label: Text('Uploaded')),
                ],
                rows: _rows.map((d) {
                  final v = (d['verification_status'] ?? '').toString();
                  return DataRow(cells: [
                    DataCell(Text(d['file_name'] ?? '')),
                    DataCell(Text(d['file_type'] ?? '—', style: const TextStyle(color: kAdminTextMuted, fontSize: 11.5))),
                    DataCell(Text((d['category'] ?? '').toString().replaceAll('_', ' '))),
                    DataCell(Text(d['owner_name'] ?? '')),
                    DataCell(AdminBadge((d['owner_role'] ?? '').toString().replaceAll('_', ' '), kAdminAccent)),
                    DataCell(v.isEmpty ? const Text('—', style: TextStyle(color: kAdminTextMuted)) : AdminBadge(v, AdminBadge.colorFor(v))),
                    DataCell(Text(fmtDate(d['created_at']))),
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
