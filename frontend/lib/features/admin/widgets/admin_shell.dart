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

/// The mobile app forces `ThemeMode.dark` globally (dark navy backgrounds,
/// near-white default text) — see main.dart. The admin panel is a light,
/// white-card dashboard that never overrode that ambient theme, so every
/// *unstyled* Material widget under it (DataTable headers/cells, dialogs,
/// buttons, checkboxes) inherited light-on-dark colors and rendered as
/// barely-visible light-gray/white text on white cards. This is the actual
/// cause of the "text is very light/faded" and "looks broken" reports — the
/// explicit `kAdminText*`-styled Text widgets were always fine; only the
/// theme-defaulted ones were invisible.
///
/// Scoping a real light [ThemeData] here (not touching AppTheme.darkTheme,
/// which every mobile Lawyer/Client/Student screen still uses untouched)
/// fixes every one of those defaulted widgets at once, panel-wide.
ThemeData buildAdminTheme(BuildContext context) {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kAdminBg,
    colorScheme: base.colorScheme.copyWith(
      brightness: Brightness.light,
      primary: kAdminAccent,
      secondary: kAdminGold,
      surface: kAdminCard,
      error: kAdminRed,
      onSurface: kAdminTextPri,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: kAdminTextPri,
      displayColor: kAdminTextPri,
    ),
    iconTheme: const IconThemeData(color: kAdminTextMuted),
    dividerColor: kAdminBorder,
    dividerTheme: const DividerThemeData(color: kAdminBorder, thickness: 1),
    cardColor: kAdminCard,
    dialogTheme: DialogThemeData(
      backgroundColor: kAdminCard,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
          color: kAdminTextPri, fontSize: 16, fontWeight: FontWeight.w800),
      contentTextStyle: const TextStyle(color: kAdminTextPri, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStateProperty.all(kAdminBg),
      headingTextStyle: const TextStyle(
          color: kAdminTextPri, fontSize: 12.5, fontWeight: FontWeight.w800),
      dataTextStyle: const TextStyle(color: kAdminTextPri, fontSize: 13),
      dividerThickness: 1,
      // Built-in Material hover support — a subtle row-hover highlight with
      // zero extra state management, applied panel-wide from one place.
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered))
          return kAdminAccent.withValues(alpha: 0.04);
        return null;
      }),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? kAdminAccent : null),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kAdminTextPri,
        side: const BorderSide(color: kAdminBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kAdminAccent),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kAdminAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kAdminBg,
      hintStyle: const TextStyle(color: kAdminTextMuted),
      labelStyle: const TextStyle(color: kAdminTextMuted),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
          color: kAdminTextPri, borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 11.5),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kAdminTextPri,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class AdminNavItem {
  final String label;
  final IconData icon;
  final String route;
  const AdminNavItem(this.label, this.icon, this.route);
}

const List<AdminNavItem> kAdminNav = [
  AdminNavItem('Dashboard', Icons.dashboard_rounded, '/admin'),
  AdminNavItem(
      'Analytics & Reports', Icons.query_stats_rounded, '/admin/analytics'),
  AdminNavItem('Users', Icons.people_alt_rounded, '/admin/users'),
  AdminNavItem('Lawyers', Icons.gavel_rounded, '/admin/lawyers'),
  AdminNavItem('Students', Icons.school_rounded, '/admin/students'),
  AdminNavItem('Clients', Icons.person_rounded, '/admin/clients'),
  AdminNavItem(
      'Consultations', Icons.event_note_rounded, '/admin/consultations'),
  AdminNavItem('Payments', Icons.payments_rounded, '/admin/payments'),
  AdminNavItem('Billing / Revenue', Icons.account_balance_wallet_rounded,
      '/admin/revenue'),
  AdminNavItem(
      'Subscriptions', Icons.workspace_premium_rounded, '/admin/subscriptions'),
  AdminNavItem(
      'Lawyer Earnings', Icons.savings_rounded, '/admin/lawyer-earnings'),
  AdminNavItem('Payouts & Settlements', Icons.account_balance_wallet_rounded,
      '/admin/payouts'),
  AdminNavItem(
      'Verification', Icons.verified_user_rounded, '/admin/verify-lawyers'),
  AdminNavItem('Documents', Icons.folder_shared_rounded, '/admin/documents'),
  AdminNavItem('Cases', Icons.cases_rounded, '/admin/cases'),
  AdminNavItem(
      'Courts / Hearings', Icons.account_balance_rounded, '/admin/hearings'),
  AdminNavItem('Notifications', Icons.notifications_active_rounded,
      '/admin/notifications'),
  AdminNavItem('Notifications Center', Icons.campaign_rounded,
      '/admin/notifications-center'),
  AdminNavItem(
      'Support / Complaints', Icons.support_agent_rounded, '/admin/support'),
  AdminNavItem('Content Management', Icons.edit_document, '/admin/content'),
  AdminNavItem('Audit Logs', Icons.shield_rounded, '/admin/audit'),
];

/// Purely a visual grouping label inserted above the nav item whose route is
/// the map key — does not affect kAdminNav, routing, or which item is
/// "active"; it only breaks the sidebar into labeled sections for scannability
/// on a 15-item menu.
const Map<String, String> _kAdminNavSectionBefore = {
  '/admin': 'OVERVIEW',
  '/admin/users': 'PEOPLE',
  '/admin/consultations': 'OPERATIONS',
  '/admin/revenue': 'FINANCE',
  '/admin/verify-lawyers': 'COMPLIANCE',
  '/admin/documents': 'RECORDS',
  '/admin/notifications': 'SYSTEM',
};

/// The persistent chrome around every admin screen: a dark sidebar with the
/// full nav list, a top bar with global search + admin identity + logout,
/// and a content area. Every admin screen wraps its own body in this rather
/// than building its own Scaffold, so navigating between sections always
/// looks like one application instead of independently-styled pages.
///
/// Desktop-first (this panel's whole reason to exist is Chrome at
/// 1366x768+), but degrades to an icon-only rail below ~1000px rather than
/// breaking, since Chrome windows do get resized.
/// Same confirm-before-signing-out pattern already used on the Lawyer/Client/
/// Student sides — this top-bar icon used to log out immediately on tap,
/// with no confirmation and no way to back out of an accidental press.
void _confirmAdminLogout(BuildContext context, AuthProvider auth) {
  showDialog(
      context: context,
      builder: (_) => AlertDialog(
            backgroundColor: kAdminCard,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.logout_rounded, color: kAdminRed, size: 22),
              SizedBox(width: 8),
              Text('Log out',
                  style: TextStyle(
                      color: kAdminTextPri, fontWeight: FontWeight.w700)),
            ]),
            content: const Text('Are you sure you want to log out?',
                style: TextStyle(color: kAdminTextMuted)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style: TextStyle(color: kAdminTextMuted))),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await auth.logout();
                  if (context.mounted) context.go('/login');
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: kAdminRed,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: const Text('Log out',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ));
}

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

    return Theme(
      data: buildAdminTheme(context),
      child: Scaffold(
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
                      // A fresh key per route makes this page's whole body
                      // fade+slide in on every navigation — a real "page
                      // transition" for a body that otherwise just swaps
                      // instantly inside the same persistent shell.
                      child:
                          _PageFadeIn(key: ValueKey(activeRoute), child: child),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Fades and slides a page body in on first build. Cheap (one
/// AnimationController, runs once), and skipped entirely for anyone with
/// reduced-motion accessibility settings.
class _PageFadeIn extends StatefulWidget {
  final Widget child;
  const _PageFadeIn({super.key, required this.child});
  @override
  State<_PageFadeIn> createState() => _PageFadeInState();
}

class _PageFadeInState extends State<_PageFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    // Inherited-widget lookups (MediaQuery.of/maybeOf included) must not
    // happen in initState — the element isn't attached to the tree yet, so
    // dependOnInheritedWidgetOfExactType throws there. This reads the
    // platform's reduce-motion flag directly instead, which needs no
    // BuildContext/inherited-widget lookup at all.
    final reduceMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _ctrl = AnimationController(
        vsync: this, duration: Duration(milliseconds: reduceMotion ? 0 : 260));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      );
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kAdminSidebar, Color(0xFF0B1524)],
        ),
      ),
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
                    gradient: const LinearGradient(
                        colors: [kAdminAccent, Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                          color: kAdminAccent.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ],
                  ),
                  child: const Icon(Icons.shield_rounded,
                      color: Colors.white, size: 18),
                ),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Libra Admin',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800),
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
              children: kAdminNav.expand((item) {
                final active = item.route == activeRoute;
                final section = _kAdminNavSectionBefore[item.route];
                return [
                  if (section != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(compact ? 0 : 20,
                          item.route == '/admin' ? 4 : 18, 12, 8),
                      child: compact
                          ? const SizedBox(height: 1)
                          : Text(section,
                              style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1)),
                    ),
                  _SidebarItem(
                    item: item,
                    active: active,
                    compact: compact,
                    onTap: () => context.go(item.route),
                  ),
                ];
              }).toList(),
            ),
          ),
        ]),
      ),
    );
  }
}

/// One sidebar row — hover highlight + a smooth (not instant) transition
/// into the active-route highlight, instead of the plain InkWell ripple this
/// used to be.
class _SidebarItem extends StatefulWidget {
  final AdminNavItem item;
  final bool active;
  final bool compact;
  final VoidCallback onTap;
  const _SidebarItem(
      {required this.item,
      required this.active,
      required this.compact,
      required this.onTap});

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.active || _hovering;
    return Tooltip(
      message: widget.compact ? widget.item.label : '',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 0 : 12, vertical: 11),
            decoration: BoxDecoration(
              color: widget.active
                  ? kAdminSidebarActive
                  : (_hovering
                      ? kAdminSidebarActive.withValues(alpha: 0.5)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              border: widget.active
                  ? const Border(left: BorderSide(color: kAdminGold, width: 3))
                  : const Border(
                      left: BorderSide(color: Colors.transparent, width: 3)),
            ),
            child: Row(
              mainAxisAlignment: widget.compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 160),
                  style: TextStyle(
                      color: highlighted ? kAdminGold : Colors.white60),
                  child: Icon(widget.item.icon,
                      color: highlighted ? kAdminGold : Colors.white60,
                      size: 19),
                ),
                if (!widget.compact) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 160),
                      style: TextStyle(
                          color: widget.active ? Colors.white : Colors.white60,
                          fontSize: 13,
                          fontWeight: widget.active
                              ? FontWeight.w700
                              : FontWeight.w400),
                      child: Text(widget.item.label,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    _resultsOverlay?.remove();
    _resultsOverlay = null;
    if (q.trim().length < 2) return;
    try {
      final res = await DioClient.instance
          .get('/admin/search', queryParameters: {'q': q});
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
    if (users.isEmpty &&
        consultations.isEmpty &&
        payments.isEmpty &&
        cases.isEmpty) return;

    final overlay = Overlay.of(context);
    _resultsOverlay = OverlayEntry(
      builder: (_) => Positioned(
        width: 380,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 46),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.scale(
                  scale: 0.97 + 0.03 * v,
                  alignment: Alignment.topCenter,
                  child: child),
            ),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 420),
                decoration: BoxDecoration(
                    color: kAdminCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kAdminBorder)),
                child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(8),
                    children: [
                      if (users.isNotEmpty)
                        _searchSection('Users', users,
                            (u) => '${u['name']} · ${u['role']}'),
                      if (consultations.isNotEmpty)
                        _searchSection(
                            'Consultations',
                            consultations,
                            (v) =>
                                '${v['client_name']} ↔ ${v['lawyer_name']} · ${v['status']}'),
                      if (payments.isNotEmpty)
                        _searchSection('Payments', payments,
                            (v) => '${v['order_id']} · ${v['status']}'),
                      if (cases.isNotEmpty)
                        _searchSection(
                            'Cases', cases, (v) => '${v['case_title']}'),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_resultsOverlay!);
  }

  Widget _searchSection(
          String label, List results, String Function(dynamic) subtitle) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(label.toUpperCase(),
                style: const TextStyle(
                    color: kAdminTextMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800)),
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

  final _searchFocus = FocusNode();
  bool _searchFocused = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: kAdminCard,
        border: const Border(bottom: BorderSide(color: kAdminBorder)),
        boxShadow: [
          BoxShadow(
              color: kAdminTextPri.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      // The title, search box, actions, identity and logout button all
      // compete for one row's width — on a narrower Chrome window this used
      // to overflow rather than shrink. LayoutBuilder drops the search box
      // and the admin's name label below a width threshold instead, the
      // same "compact mode" approach the sidebar already uses.
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Row(children: [
          Flexible(
            child: Text(widget.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: kAdminTextPri,
                    fontSize: 19,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 16),
          if (!compact)
            CompositedTransformTarget(
              link: _layerLink,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 260,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _searchFocused ? kAdminAccent : Colors.transparent,
                      width: 1.4),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onTap: () => setState(() => _searchFocused = true),
                  onTapOutside: (_) {
                    _searchFocus.unfocus();
                    setState(() => _searchFocused = false);
                  },
                  onChanged: (v) => _search(v),
                  style: const TextStyle(fontSize: 13, color: kAdminTextPri),
                  decoration: InputDecoration(
                    hintText: 'Search users, consultations, payments, cases…',
                    hintStyle:
                        const TextStyle(fontSize: 12, color: kAdminTextMuted),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 18,
                        color: _searchFocused ? kAdminAccent : kAdminTextMuted),
                    filled: true,
                    fillColor: kAdminBg,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
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
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
          ),
          if (!compact) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(auth.user?.name ?? 'Admin',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: kAdminTextPri,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ],
          const SizedBox(width: 12),
          _HoverIconButton(
            tooltip: 'Log out',
            icon: Icons.logout_rounded,
            onPressed: () => _confirmAdminLogout(context, auth),
          ),
        ]);
      }),
    );
  }
}

/// An IconButton with a subtle hover background — the panel's other
/// clickable surfaces (sidebar, chips, stat cards) all have a hover state;
/// bare top-bar IconButtons were the one thing left with zero feedback.
class _HoverIconButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  const _HoverIconButton(
      {required this.tooltip, required this.icon, required this.onPressed});

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _hovering ? kAdminBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: IconButton(
            tooltip: widget.tooltip,
            icon: Icon(widget.icon,
                color: _hovering ? kAdminRed : kAdminTextMuted, size: 20),
            onPressed: widget.onPressed,
          ),
        ),
      );
}
