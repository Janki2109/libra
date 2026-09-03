import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_user_detail_dialog.dart';
import '../widgets/admin_widgets.dart';

class AdminClientsScreen extends StatefulWidget {
  const AdminClientsScreen({super.key});
  @override
  State<AdminClientsScreen> createState() => _AdminClientsScreenState();
}

class _AdminClientsScreenState extends State<AdminClientsScreen> {
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
      final res = await _repo.clients(status: _status, search: _search, page: _page);
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

  Future<void> _toggleActive(String id, bool active) async {
    try {
      await _repo.setUserActive(id, active);
      _load();
    } on AdminException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/clients',
      title: 'Clients',
      actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      child: AdminSectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            AdminSearchField(
                hint: 'Search name or email…',
                onChanged: (v) {
                  _search = v;
                  _page = 1;
                  _load();
                }),
            for (final s in const [('', 'Any status'), ('active', 'Active'), ('suspended', 'Suspended')])
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
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Lawyers Consulted')),
                  DataColumn(label: Text('Consultations')),
                  DataColumn(label: Text('Completed')),
                  DataColumn(label: Text('Cancelled')),
                  DataColumn(label: Text('Payments')),
                  DataColumn(label: Text('Amount Spent')),
                  DataColumn(label: Text('Registered')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: _rows.map((cl) {
                  final active = cl['is_active'] == true;
                  return DataRow(cells: [
                    DataCell(Text(cl['name'] ?? ''), onTap: () => showAdminUserDetail(context, cl['id'])),
                    DataCell(Text(cl['email'] ?? '', style: const TextStyle(color: kAdminTextMuted))),
                    DataCell(AdminBadge(active ? 'Active' : 'Suspended', AdminBadge.colorFor(active ? 'active' : 'suspended'))),
                    DataCell(Text('${cl['total_lawyers_consulted'] ?? 0}')),
                    DataCell(Text('${cl['total_consultations'] ?? 0}')),
                    DataCell(Text('${cl['completed_consultations'] ?? 0}')),
                    DataCell(Text('${cl['cancelled_consultations'] ?? 0}')),
                    DataCell(Text('${cl['total_payments'] ?? 0}')),
                    DataCell(Text(fmtRupees(cl['total_amount_spent'] as num?))),
                    DataCell(Text(fmtDate(cl['created_at']))),
                    DataCell(IconButton(
                      icon: Icon(active ? Icons.block_rounded : Icons.check_circle_rounded,
                          size: 18, color: active ? kAdminRed : kAdminGreen),
                      onPressed: () => _toggleActive(cl['id'], !active),
                    )),
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
