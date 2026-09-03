import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_user_detail_dialog.dart';
import '../widgets/admin_widgets.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];
  bool _hasMore = false;
  int _page = 1;

  String _role = '';
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
      final res = await _repo.users(role: _role, status: _status, search: _search, page: _page);
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

  void _setPage(int p) {
    setState(() => _page = p);
    _load();
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
      activeRoute: '/admin/users',
      title: 'Users',
      actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      child: AdminSectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            AdminSearchField(
                hint: 'Search name, email, phone…',
                onChanged: (v) {
                  _search = v;
                  _page = 1;
                  _load();
                }),
            for (final r in const [
              ('', 'All'),
              ('lawyer', 'Lawyers'),
              ('law_student', 'Students'),
              ('client', 'Clients'),
            ])
              AdminFilterChip(
                  label: r.$2,
                  selected: _role == r.$1,
                  onTap: () {
                    setState(() {
                      _role = r.$1;
                      _page = 1;
                    });
                    _load();
                  }),
            const SizedBox(width: 12),
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
                  DataColumn(label: Text('Phone')),
                  DataColumn(label: Text('Role')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Consultations')),
                  DataColumn(label: Text('Amount Paid')),
                  DataColumn(label: Text('Registered')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: _rows.map((u) {
                  final active = u['is_active'] == true;
                  return DataRow(cells: [
                    DataCell(Text(u['name'] ?? ''), onTap: () => showAdminUserDetail(context, u['id'])),
                    DataCell(Text(u['email'] ?? '', style: const TextStyle(color: kAdminTextMuted))),
                    DataCell(Text(u['phone'] ?? '-')),
                    DataCell(AdminBadge((u['role_name'] ?? '').toString().replaceAll('_', ' '), kAdminAccent)),
                    DataCell(AdminBadge(active ? 'Active' : 'Suspended', AdminBadge.colorFor(active ? 'active' : 'suspended'))),
                    DataCell(Text('${u['total_consultations'] ?? 0}')),
                    DataCell(Text(fmtRupees(u['total_amount_paid'] as num?))),
                    DataCell(Text(fmtDate(u['created_at']))),
                    DataCell(Row(children: [
                      IconButton(
                        icon: Icon(active ? Icons.block_rounded : Icons.check_circle_rounded,
                            size: 18, color: active ? kAdminRed : kAdminGreen),
                        tooltip: active ? 'Suspend' : 'Activate',
                        onPressed: () => _toggleActive(u['id'], !active),
                      ),
                      IconButton(
                        icon: const Icon(Icons.visibility_rounded, size: 18, color: kAdminAccent),
                        tooltip: 'View',
                        onPressed: () => showAdminUserDetail(context, u['id']),
                      ),
                    ])),
                  ]);
                }).toList(),
              ),
            ),
          AdminPager(page: _page, hasMore: _hasMore, loading: _loading, onPageChange: _setPage),
        ]),
      ),
    );
  }
}
