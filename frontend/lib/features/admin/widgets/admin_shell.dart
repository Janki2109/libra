import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/services/dio_client.dart';
import '../../auth/providers/auth_provider.dart';

// The Admin Panel's own palette — deliberately distinct from the
// mobile Lawyer/Student/Client screens (which keep their existing colors
// untouched). This is the only part of the app redesigned for this task.
const kAdminBg = Color(0xFFF4F6F9);
const kAdminCard = Color(0xFFFFFFFF);
const kAdminSidebar = Color(0xFF101B2D);
const kAdminSidebarActive = Color(0xFF1B2C47);
const kAdminAccent = Color(0xFF2563EB);
const kAdminGold = Color(0xFFD4AF37);
const kAdminBorder = Color(0xFFE3E8EF);
const kAdminTextPri = Color(0xFF101B2D);
const kAdminTextMuted = Color(0xFF64748B);
const kAdminGreen = Color(0xFF16A34A);
const kAdminRed = Color(0xFFDC2626);
const kAdminAmber = Color(0xFFD97706);

class AdminNavItem {
  final String label;
  final IconData icon;
  final String route;
  const AdminNavItem(this.label, this.icon, this.route);
}

const List<AdminNavItem> kAdminNav = [
  AdminNavItem('Dashboard', Icons.dashboard_rounded, '/admin'),
  AdminNavItem('Users', Icons.people_alt_rounded, '/admin/users'),
  AdminNavItem('Lawyers', Icons.gavel_rounded, '/admin/lawyers'),
  AdminNavItem('Students', Icons.school_rounded, '/admin/students'),
  AdminNavItem('Clients', Icons.person_rounded, '/admin/clients'),
  AdminNavItem('Consultations', Icons.event_note_rounded, '/admin/consultations'),
  AdminNavItem('Payments', Icons.payments_rounded, '/admin/payments'),
  AdminNavItem('Billing / Revenue', Icons.account_balance_wallet_rounded, '/admin/revenue'),
  AdminNavItem('Lawyer Earnings', Icons.savings_rounded, '/admin/lawyer-earnings'),
  AdminNavItem('Verification', Icons.verified_user_rounded, '/admin/verify-lawyers'),
  AdminNavItem('Documents', Icons.folder_shared_rounded, '/admin/documents'),
  AdminNavItem('Cases', Icons.cases_rounded, '/admin/cases'),
  AdminNavItem('Courts / Hearings', Icons.account_balance_rounded, '/admin/hearings'),
  AdminNavItem('Notifications', Icons.notifications_active_rounded, '/admin/notifications'),
  AdminNavItem('Settings', Icons.settings_rounded, '/admin/audit'),
];

/// The persistent chrome around every admin screen: a dark sidebar with the
/// full nav list, a top bar with global search + admin identity + logout,
/// and a content area. Every admin screen wraps its own body in this rather
/// than building its own Scaffold, so navigating between sections always
/// looks like one application instead of independently-styled pages.
///
/// Desktop-first (this panel's whole reason to exist is Chrome at
/// 1366x768+), but degrades to an icon-only rail below ~1000px rather than
/// breaking, since Chrome windows do get resized.
class AdminShell extends StatelessWidget {
  final String activeRoute;
  final String title;
  final Widget child;
  final List<Widget>? actions;

  const AdminShell({
    super.key,
    required this.activeRoute,
    required this.title,
    required this.child,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final compact = width < 1000;

    return Scaffold(
      backgroundColor: kAdminBg,
      body: Row(children: [
        _Sidebar(activeRoute: activeRoute, compact: compact),
        Expanded(
          child: Column(children: [
            _TopBar(title: title, actions: actions),
            Expanded(
              child: ClipRect(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: child,
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final String activeRoute;
  final bool compact;
  const _Sidebar({required this.activeRoute, required this.compact});

  @override
  Widget build(BuildContext context) {
    final width = compact ? 72.0 : 248.0;
    return Container(
      width: width,
      color: kAdminSidebar,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            child: Row(
              mainAxisAlignment:
                  compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: kAdminAccent, borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.shield_rounded, color: Colors.white, size: 18),
                ),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Libra Admin',
                        style: TextStyle(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ],
            ),
          ),
          const Divider(color: Color(0xFF1E2E47), height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: kAdminNav.map((item) {
                final active = item.route == activeRoute;
                return Tooltip(
                  message: compact ? item.label : '',
                  child: InkWell(
                    onTap: () => context.go(item.route),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      padding: EdgeInsets.symmetric(
                          horizontal: compact ? 0 : 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: active ? kAdminSidebarActive : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment:
                            compact ? MainAxisAlignment.center : MainAxisAlignment.start,
                        children: [
                          Icon(item.icon,
                              color: active ? kAdminGold : Colors.white60, size: 19),
                          if (!compact) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(item.label,
                                  style: TextStyle(
                                      color: active ? Colors.white : Colors.white60,
                                      fontSize: 13,
                                      fontWeight: active ? FontWeight.w700 : FontWeight.w400),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TopBar extends StatefulWidget {
  final String title;
  final List<Widget>? actions;
  const _TopBar({required this.title, this.actions});

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  final _searchCtrl = TextEditingController();
  OverlayEntry? _resultsOverlay;
  final _layerLink = LayerLink();

  @override
  void dispose() {
    _resultsOverlay?.remove();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    _resultsOverlay?.remove();
    _resultsOverlay = null;
    if (q.trim().length < 2) return;
    try {
      final res = await DioClient.instance.get('/admin/search', queryParameters: {'q': q});
      final data = res.data['data'] as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      _showResults(data);
    } catch (_) {}
  }

  void _showResults(Map<String, dynamic> data) {
    final users = (data['users'] as List?) ?? [];
    final consultations = (data['consultations'] as List?) ?? [];
    final payments = (data['payments'] as List?) ?? [];
    final cases = (data['cases'] as List?) ?? [];
    if (users.isEmpty && consultations.isEmpty && payments.isEmpty && cases.isEmpty) return;

    final overlay = Overlay.of(context);
    _resultsOverlay = OverlayEntry(
      builder: (_) => Positioned(
        width: 380,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 46),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 420),
              decoration: BoxDecoration(
                  color: kAdminCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kAdminBorder)),
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(8), children: [
                if (users.isNotEmpty) _searchSection('Users', users, (u) => '${u['name']} · ${u['role']}'),
                if (consultations.isNotEmpty)
                  _searchSection('Consultations', consultations,
                      (v) => '${v['client_name']} ↔ ${v['lawyer_name']} · ${v['status']}'),
                if (payments.isNotEmpty)
                  _searchSection('Payments', payments,
                      (v) => '${v['order_id']} · ${v['status']}'),
                if (cases.isNotEmpty)
                  _searchSection('Cases', cases, (v) => '${v['case_title']}'),
              ]),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_resultsOverlay!);
  }

  Widget _searchSection(String label, List results, String Function(dynamic) subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(label.toUpperCase(),
                style: const TextStyle(
                    color: kAdminTextMuted, fontSize: 10, fontWeight: FontWeight.w800)),
          ),
          ...results.map((r) => ListTile(
                dense: true,
                title: Text(subtitle(r), style: const TextStyle(fontSize: 13)),
                onTap: () {
                  _resultsOverlay?.remove();
                  _resultsOverlay = null;
                },
              )),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: kAdminCard,
        border: Border(bottom: BorderSide(color: kAdminBorder)),
      ),
      child: Row(children: [
        Text(widget.title,
            style: const TextStyle(
                color: kAdminTextPri, fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(width: 24),
        CompositedTransformTarget(
          link: _layerLink,
          child: SizedBox(
            width: 320,
            height: 38,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => _search(v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search users, consultations, payments, cases…',
                hintStyle: const TextStyle(fontSize: 12, color: kAdminTextMuted),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: kAdminTextMuted),
                filled: true,
                fillColor: kAdminBg,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
        const Spacer(),
        if (widget.actions != null) ...widget.actions!,
        const SizedBox(width: 12),
        CircleAvatar(
          radius: 16,
          backgroundColor: kAdminAccent,
          child: Text((auth.user?.name ?? 'A').substring(0, 1).toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
        const SizedBox(width: 8),
        Text(auth.user?.name ?? 'Admin',
            style: const TextStyle(color: kAdminTextPri, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Log out',
          icon: const Icon(Icons.logout_rounded, color: kAdminTextMuted, size: 20),
          onPressed: () async {
            await auth.logout();
            if (context.mounted) context.go('/login');
          },
        ),
      ]),
    );
  }
}
