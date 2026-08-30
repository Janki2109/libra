import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFF5ECD7);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF5C3317);
const _brownDark = Color(0xFF3D2008);
const _border = Color(0xFFD4B896);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF8B5E3C);
const _green = Color(0xFF2E8B57);
const _red = Color(0xFFD9534F);

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<dynamic> _lawyers = [];
  List<dynamic> _clients = [];
  List<dynamic> _students = [];
  bool _loading = true;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance.get('/admin/users');
      final all = res.data['data'] as List? ?? [];
      setState(() {
        _lawyers = all
            .where(
                (u) => u['role_name'] == 'lawyer' || u['role_name'] == 'admin')
            .toList();
        _clients = all.where((u) => u['role_name'] == 'client').toList();
        _students = all.where((u) => u['role_name'] == 'law_student').toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateUser(String userId, String action) async {
    try {
      String endpoint;
      Map<String, dynamic> data = {};

      if (action == 'suspend') {
        endpoint = '/admin/users/$userId';
        data = {'is_active': false};
      } else if (action == 'activate') {
        endpoint = '/admin/users/$userId';
        data = {'is_active': true};
      } else {
        endpoint = '/admin/users/$userId/delete';
        data = {};
      }

      if (action == 'delete') {
        await DioClient.instance.delete(endpoint);
      } else {
        await DioClient.instance.put(endpoint, data: data);
      }

      HapticFeedback.heavyImpact();
      _load();

      if (mounted) {
        final msg = action == 'suspend'
            ? 'User suspended!'
            : action == 'activate'
                ? 'User activated!'
                : 'User deleted!';
        final color = action == 'activate' ? _green : _red;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: _red));
    }
  }

  void _showUserActions(dynamic user) {
    final isActive = user['is_active'] == true;
    final name = user['name'] ?? 'User';
    final role = user['role_name'] ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: _bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: _border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          // User info
          Row(children: [
            Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    gradient:
                        const LinearGradient(colors: [_brown, _brownDark]),
                    shape: BoxShape.circle),
                child: Center(
                    child: Text((name)[0].toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 22)))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      style: const TextStyle(
                          color: _textPri,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  Text(user['email'] ?? '',
                      style: const TextStyle(color: _textMuted, fontSize: 12)),
                  Text(role.replaceAll('_', ' ').toUpperCase(),
                      style: const TextStyle(
                          color: _brown,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ])),
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: isActive
                        ? _green.withValues(alpha: 0.1)
                        : _red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(isActive ? 'ACTIVE' : 'SUSPENDED',
                    style: TextStyle(
                        color: isActive ? _green : _red,
                        fontSize: 10,
                        fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFFD4B896)),
          const SizedBox(height: 8),
          // User details
          _InfoRow('Phone', user['phone'] ?? '-'),
          _InfoRow(
              'Joined',
              (user['created_at'] ?? '').toString().length >= 10
                  ? (user['created_at'] ?? '').toString().substring(0, 10)
                  : '-'),
          _InfoRow(
              'Last Login',
              (user['last_login_at'] ?? '').toString().length >= 10
                  ? (user['last_login_at'] ?? '').toString().substring(0, 10)
                  : 'Never'),
          const SizedBox(height: 16),
          // Actions
          if (isActive) ...[
            SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _confirmAction(user['id'], 'suspend', name);
                  },
                  icon: const Icon(Icons.block_rounded,
                      color: Colors.white, size: 16),
                  label: const Text('Suspend Account',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                )),
          ] else ...[
            SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _updateUser(user['id'], 'activate');
                  },
                  icon: const Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 16),
                  label: const Text('Activate Account',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                )),
          ],
          const SizedBox(height: 10),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _confirmAction(user['id'], 'delete', name);
                },
                icon: const Icon(Icons.delete_forever_rounded,
                    color: _red, size: 16),
                label: const Text('Delete Account',
                    style: TextStyle(color: _red, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _confirmAction(String userId, String action, String name) {
    final isDelete = action == 'delete';
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: _bgCard,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(isDelete ? 'Delete Account?' : 'Suspend Account?',
                  style: TextStyle(
                      color: isDelete ? _red : const Color(0xFFE65100),
                      fontWeight: FontWeight.w800)),
              content: Text(
                  isDelete
                      ? 'Are you sure you want to permanently delete $name\'s account? This cannot be undone.'
                      : 'Are you sure you want to suspend $name\'s account? They will lose access immediately.',
                  style: const TextStyle(color: _textMuted, fontSize: 13)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(color: _textMuted))),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _updateUser(userId, action);
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isDelete ? _red : const Color(0xFFE65100),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: Text(isDelete ? 'Yes, Delete' : 'Yes, Suspend',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ));
  }

  Widget _InfoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(color: _textMuted, fontSize: 12))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: _textPri,
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // Header
        Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_brown, _brownDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: SafeArea(
              bottom: false,
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
                    child: Row(children: [
                      IconButton(
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white),
                          onPressed: () => context.pop()),
                      const Expanded(
                          child: Text('User Management',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700))),
                      IconButton(
                          icon: const Icon(Icons.refresh_rounded,
                              color: Colors.white),
                          onPressed: _load),
                    ])),
                // Search
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12)),
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(color: _textPri, fontSize: 14),
                        onChanged: (v) =>
                            setState(() => _search = v.toLowerCase()),
                        decoration: const InputDecoration(
                            hintText: 'Search by name or email...',
                            hintStyle:
                                TextStyle(color: _textMuted, fontSize: 13),
                            prefixIcon: Icon(Icons.search_rounded,
                                color: _brown, size: 20),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12)),
                      ),
                    )),
                // Tabs
                TabBar(
                    controller: _tabCtrl,
                    indicatorColor: const Color(0xFFFFD700),
                    indicatorWeight: 3,
                    labelColor: const Color(0xFFFFD700),
                    unselectedLabelColor: Colors.white60,
                    tabs: [
                      Tab(text: 'Lawyers (${_lawyers.length})'),
                      Tab(text: 'Clients (${_clients.length})'),
                      Tab(text: 'Students (${_students.length})'),
                    ]),
              ])),
        ),

        // Stats row
        Container(
            color: _bgCard,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatChip(
                      'Total',
                      '${_lawyers.length + _clients.length + _students.length}',
                      _brown),
                  _StatChip(
                      'Active',
                      '${[
                        ..._lawyers,
                        ..._clients,
                        ..._students
                      ].where((u) => u['is_active'] == true).length}',
                      _green),
                  _StatChip(
                      'Suspended',
                      '${[
                        ..._lawyers,
                        ..._clients,
                        ..._students
                      ].where((u) => u['is_active'] != true).length}',
                      _red),
                ])),

        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _brown))
                : TabBarView(controller: _tabCtrl, children: [
                    _buildList(_lawyers),
                    _buildList(_clients),
                    _buildList(_students),
                  ])),
      ]),
    );
  }

  Widget _buildList(List<dynamic> list) {
    final filtered = _search.isEmpty
        ? list
        : list
            .where((u) =>
                (u['name'] ?? '').toLowerCase().contains(_search) ||
                (u['email'] ?? '').toLowerCase().contains(_search))
            .toList();

    if (filtered.isEmpty)
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.people_rounded, color: _brown.withValues(alpha: 0.3), size: 56),
        const SizedBox(height: 12),
        Text(_search.isEmpty ? 'No users found' : 'No results for "$_search"',
            style: const TextStyle(color: _textMuted, fontSize: 15)),
      ]));

    return RefreshIndicator(
      color: _brown,
      backgroundColor: _bgCard,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final u = filtered[i];
          final isActive = u['is_active'] == true;
          final name = u['name'] ?? 'User';
          final initial = name[0].toUpperCase();
          final role = (u['role_name'] ?? '').replaceAll('_', ' ');

          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _showUserActions(u);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isActive ? _border : _red.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                        color: _brown.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
                  ]),
              child: Row(children: [
                // Avatar with status dot
                Stack(children: [
                  Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: isActive
                                  ? [_brown, _brownDark]
                                  : [_red.withValues(alpha: 0.6), _red]),
                          shape: BoxShape.circle),
                      child: Center(
                          child: Text(initial,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20)))),
                  Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                              color: isActive ? _green : _red,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 1.5)))),
                ]),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(name,
                          style: const TextStyle(
                              color: _textPri,
                              fontWeight: FontWeight.w700,
                              fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(u['email'] ?? '',
                          style:
                              const TextStyle(color: _textMuted, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(role.toUpperCase(),
                          style: const TextStyle(
                              color: _brown,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ])),
                // Quick actions
                Row(children: [
                  if (isActive)
                    GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _confirmAction(u['id'], 'suspend', name);
                        },
                        child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                                color: const Color(0xFFE65100).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.block_rounded,
                                color: Color(0xFFE65100), size: 16)))
                  else
                    GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _updateUser(u['id'], 'activate');
                        },
                        child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                                color: _green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.check_circle_rounded,
                                color: _green, size: 16))),
                  GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _confirmAction(u['id'], 'delete', name);
                      },
                      child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                              color: _red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.delete_rounded,
                              color: _red, size: 16))),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _StatChip(String label, String value, Color color) =>
      Column(children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: _textMuted, fontSize: 10)),
      ]);
}
