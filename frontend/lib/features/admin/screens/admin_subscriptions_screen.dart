import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/auto_refresh_service.dart';
import '../../lawyer/utils/browser_download.dart';
import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

/// Super Admin → Subscriptions.
///
/// Subscriptions in this app belong to a FIRM, not an individual user (see
/// admin_subscriptions_controller.go's doc comment) — only a lawyer's
/// practice ever subscribes, so every row here is shown against the firm's
/// earliest-registered lawyer. There is no GST/platform-fee/discount/refund
/// concept anywhere in subscription billing; those fields render "N/A"
/// rather than a fabricated figure.
class AdminSubscriptionsScreen extends StatefulWidget {
  const AdminSubscriptionsScreen({super.key});
  @override
  State<AdminSubscriptionsScreen> createState() =>
      _AdminSubscriptionsScreenState();
}

class _AdminSubscriptionsScreenState extends State<AdminSubscriptionsScreen>
    with SingleTickerProviderStateMixin {
  final _repo = AdminRepository();
  late TabController _tabCtrl;

  bool _statsLoading = true;
  Map<String, dynamic> _stats = {};

  bool _plansLoading = true;
  List<dynamic> _plans = [];

  bool _revenueLoading = true;
  Map<String, dynamic> _revenue = {};

  // Shared filter state for the Active/Premium/Expired/Cancelled list tabs.
  String _search = '';
  String _planFilter = '';
  DateTimeRange? _dateRange;

  bool _listLoading = true;
  List<dynamic> _activeRows = [];
  List<dynamic> _premiumRows = [];
  List<dynamic> _expiredRows = [];
  List<dynamic> _cancelledRows = [];
  int _page = 1;
  bool _hasMore = false;

  bool _paymentsLoading = true;
  List<dynamic> _payments = [];
  int _paymentsPage = 1;
  bool _paymentsHasMore = false;
  String _paymentStatusFilter = '';

  static const _tabs = [
    'Active',
    'Premium',
    'Plans',
    'Revenue',
    'Expired',
    'Cancelled',
    'Payments'
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) _loadForCurrentTab(silent: false);
    });
    _loadStats();
    _loadPlans();
    _loadRevenue();
    _loadForCurrentTab(silent: false);
    // Global 3-second auto-refresh — new subscriptions/payments/cancellations
    // show up here without a manual reload, same mechanism used app-wide
    // (see AutoRefreshService).
    AutoRefreshService.instance.register('admin_subscriptions', () async {
      await Future.wait([
        _loadStats(silent: true),
        _loadPlans(silent: true),
        _loadRevenue(silent: true),
        _loadForCurrentTab(silent: true),
      ]);
    });
  }

  @override
  void dispose() {
    AutoRefreshService.instance.unregister('admin_subscriptions');
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStats({bool silent = false}) async {
    if (!silent) setState(() => _statsLoading = true);
    try {
      final res = await _repo.subscriptionStats();
      if (!mounted) return;
      setState(() {
        _stats = (res['data'] as Map<String, dynamic>?) ?? {};
        _statsLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _loadPlans({bool silent = false}) async {
    if (!silent) setState(() => _plansLoading = true);
    try {
      final res = await _repo.subscriptionPlans();
      if (!mounted) return;
      setState(() {
        _plans = (res['data'] as List?) ?? [];
        _plansLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _plansLoading = false);
    }
  }

  Future<void> _loadRevenue({bool silent = false}) async {
    if (!silent) setState(() => _revenueLoading = true);
    try {
      final res = await _repo.subscriptionRevenue();
      if (!mounted) return;
      setState(() {
        _revenue = (res['data'] as Map<String, dynamic>?) ?? {};
        _revenueLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _revenueLoading = false);
    }
  }

  String? get _fromStr => _dateRange != null
      ? DateFormat('yyyy-MM-dd').format(_dateRange!.start)
      : null;
  String? get _toStr => _dateRange != null
      ? DateFormat('yyyy-MM-dd').format(_dateRange!.end)
      : null;

  Future<void> _loadForCurrentTab({required bool silent}) async {
    final tab = _tabs[_tabCtrl.index];
    if (tab == 'Payments') {
      await _loadPayments(silent: silent);
      return;
    }
    if (tab == 'Plans' || tab == 'Revenue')
      return; // those have their own loaders
    await _loadList(tab, silent: silent);
  }

  Future<void> _loadList(String tab, {bool silent = false}) async {
    if (!silent) setState(() => _listLoading = true);
    try {
      final res = await _repo.subscriptions(
        status: tab == 'Active'
            ? 'active'
            : tab == 'Expired'
                ? 'expired'
                : tab == 'Cancelled'
                    ? 'cancelled'
                    : null,
        premiumOnly: tab == 'Premium',
        plan: _planFilter,
        search: _search,
        from: _fromStr,
        to: _toStr,
        page: _page,
      );
      if (!mounted) return;
      setState(() {
        final rows = (res['data'] as List?) ?? [];
        switch (tab) {
          case 'Active':
            _activeRows = rows;
            break;
          case 'Premium':
            _premiumRows = rows;
            break;
          case 'Expired':
            _expiredRows = rows;
            break;
          case 'Cancelled':
            _cancelledRows = rows;
            break;
        }
        _hasMore = (res['meta']?['has_more'] as bool?) ?? false;
        _listLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _listLoading = false);
    }
  }

  Future<void> _loadPayments({bool silent = false}) async {
    if (!silent) setState(() => _paymentsLoading = true);
    try {
      final res = await _repo.subscriptionPayments(
        search: _search,
        plan: _planFilter,
        status: _paymentStatusFilter,
        from: _fromStr,
        to: _toStr,
        page: _paymentsPage,
      );
      if (!mounted) return;
      setState(() {
        _payments = (res['data'] as List?) ?? [];
        _paymentsHasMore = (res['meta']?['has_more'] as bool?) ?? false;
        _paymentsLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _paymentsLoading = false);
    }
  }

  void _applyFilters() {
    _page = 1;
    _paymentsPage = 1;
    _loadForCurrentTab(silent: false);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: DateTime(now.year + 1),
        initialDateRange: _dateRange);
    if (picked != null) {
      setState(() => _dateRange = picked);
      _applyFilters();
    }
  }

  List<dynamic> get _currentRows {
    switch (_tabs[_tabCtrl.index]) {
      case 'Active':
        return _activeRows;
      case 'Premium':
        return _premiumRows;
      case 'Expired':
        return _expiredRows;
      case 'Cancelled':
        return _cancelledRows;
      default:
        return [];
    }
  }

  num _n(String key) => (_stats[key] as num?) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/subscriptions',
      title: 'Subscriptions',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
          onPressed: () {
            _loadStats();
            _loadPlans();
            _loadRevenue();
            _loadForCurrentTab(silent: false);
          },
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _statsGrid(),
        const SizedBox(height: 20),
        _quickDateChip(),
        const SizedBox(height: 12),
        AdminSectionCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            labelColor: kAdminAccent,
            unselectedLabelColor: kAdminTextMuted,
            indicatorColor: kAdminAccent,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 720,
          child: TabBarView(controller: _tabCtrl, children: [
            _listTab('Active'),
            _listTab('Premium'),
            _plansTab(),
            _revenueTab(),
            _listTab('Expired'),
            _listTab('Cancelled'),
            _paymentsTab(),
          ]),
        ),
      ]),
    );
  }

  Widget _quickDateChip() => Wrap(spacing: 8, runSpacing: 8, children: [
        GestureDetector(
          onTap: _pickDateRange,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _dateRange != null
                  ? kAdminAccent.withValues(alpha: 0.1)
                  : kAdminCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: _dateRange != null ? kAdminAccent : kAdminBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.date_range_rounded,
                  size: 15,
                  color: _dateRange != null ? kAdminAccent : kAdminTextMuted),
              const SizedBox(width: 6),
              Text(
                  _dateRange == null
                      ? 'Date range'
                      : '${DateFormat('d MMM').format(_dateRange!.start)} - ${DateFormat('d MMM').format(_dateRange!.end)}',
                  style: TextStyle(
                      color: _dateRange != null ? kAdminAccent : kAdminTextPri,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
              if (_dateRange != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    setState(() => _dateRange = null);
                    _applyFilters();
                  },
                  child: const Icon(Icons.close_rounded,
                      size: 14, color: kAdminAccent),
                ),
              ],
            ]),
          ),
        ),
      ]);

  Widget _statsGrid() {
    if (_statsLoading) return const AdminStatGridSkeleton(count: 8);
    final f =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    // Tapping a card jumps straight to the tab it summarizes — _tabs is
    // ['Active','Premium','Plans','Revenue','Expired','Cancelled','Payments'].
    final cards = [
      (
        'Total Subscriptions',
        '${_n('total_subscriptions')}',
        Icons.workspace_premium_rounded,
        kAdminAccent,
        0
      ),
      (
        'Active Subscriptions',
        '${_n('active_subscriptions')}',
        Icons.check_circle_rounded,
        kAdminGreen,
        0
      ),
      (
        'Premium Users',
        '${_n('premium_users')}',
        Icons.diamond_rounded,
        kAdminGold,
        1
      ),
      (
        'Expired Subscriptions',
        '${_n('expired_subscriptions')}',
        Icons.event_busy_rounded,
        kAdminTextMuted,
        4
      ),
      (
        'Cancelled Subscriptions',
        '${_n('cancelled_subscriptions')}',
        Icons.cancel_rounded,
        kAdminRed,
        5
      ),
      (
        'Total Subscription Revenue',
        f.format(_n('total_revenue')),
        Icons.account_balance_wallet_rounded,
        kAdminGreen,
        3
      ),
      (
        'This Month Revenue',
        f.format(_n('month_revenue')),
        Icons.calendar_month_rounded,
        kAdminAccent,
        3
      ),
      (
        'Active Plans',
        '${_n('active_plans')}',
        Icons.list_alt_rounded,
        const Color(0xFF7C3AED),
        2
      ),
    ];
    return AdminStatGrid(
      cards: cards.asMap().entries.map((e) {
        final i = e.key;
        final c = e.value;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 200 + i * 30),
          curve: Curves.easeOut,
          builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                  offset: Offset(0, 10 * (1 - v)), child: child)),
          child: AdminStatCard(
            label: c.$1,
            value: c.$2,
            icon: c.$3,
            color: c.$4,
            onTap: () => _tabCtrl.animateTo(c.$5),
          ),
        );
      }).toList(),
    );
  }

  // ── Active / Premium / Expired / Cancelled tabs ──
  Widget _listTab(String tab) {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AdminSearchField(
                hint: 'Search firm, owner name or email…',
                onChanged: (v) {
                  _search = v;
                  _applyFilters();
                },
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: _planFilter.isEmpty ? null : _planFilter,
                  hint: const Text('All plans',
                      style: TextStyle(fontSize: 12.5, color: kAdminTextMuted)),
                  isDense: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: kAdminBg,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All plans')),
                    ..._plans.map((p) => DropdownMenuItem(
                        value: p['name'] as String,
                        child: Text(p['display_name'] ?? p['name'] ?? ''))),
                  ],
                  onChanged: (v) {
                    setState(() => _planFilter = v ?? '');
                    _applyFilters();
                  },
                ),
              ),
              OutlinedButton.icon(
                  onPressed: () => _exportCsv(tab, _currentRows),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('CSV')),
              OutlinedButton.icon(
                  onPressed: () => _exportPdf(tab, _currentRows),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                  label: const Text('PDF')),
            ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 540,
          child: _listLoading
              ? const AdminTableSkeleton(columns: 9)
              : _currentRows.isEmpty
                  ? const AdminEmptyState()
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(kAdminBg),
                          columns: const [
                            DataColumn(label: Text('Firm / Owner')),
                            DataColumn(label: Text('Email')),
                            DataColumn(label: Text('Role')),
                            DataColumn(label: Text('Plan')),
                            DataColumn(label: Text('Price')),
                            DataColumn(label: Text('Start Date')),
                            DataColumn(label: Text('Expiry Date')),
                            DataColumn(label: Text('Days Left')),
                            DataColumn(label: Text('Payment')),
                            DataColumn(label: Text('Status')),
                          ],
                          rows: _currentRows.map((s) {
                            final name =
                                (s['owner_name'] ?? '').toString().isNotEmpty
                                    ? s['owner_name']
                                    : s['firm_name'] ?? '';
                            final email =
                                (s['owner_email'] ?? '').toString().isNotEmpty
                                    ? s['owner_email']
                                    : s['firm_email'] ?? '';
                            final days = s['days_remaining'];
                            return DataRow(
                              onSelectChanged: (_) => _showDetail(s['id']),
                              cells: [
                                DataCell(Text(name)),
                                DataCell(Text(email,
                                    style: const TextStyle(
                                        color: kAdminTextMuted))),
                                DataCell(const Text('LAWYER')),
                                DataCell(Text(s['plan_display_name'] ?? '-')),
                                DataCell(
                                    Text(fmtRupees(s['plan_price'] as num?))),
                                DataCell(Text(fmtDate(s['start_date']))),
                                DataCell(Text(fmtDate(s['current_period_end']
                                            ?.toString()
                                            .isNotEmpty ==
                                        true
                                    ? s['current_period_end']
                                    : s['trial_ends_at']))),
                                DataCell(Text(days == null ? '-' : '$days d',
                                    style: TextStyle(
                                        color: days != null && (days as int) < 0
                                            ? kAdminRed
                                            : kAdminTextPri))),
                                DataCell(AdminBadge(
                                    s['payment_status'] ?? '',
                                    AdminBadge.colorFor(
                                        s['payment_status'] ?? ''))),
                                DataCell(AdminBadge(s['status'] ?? '',
                                    AdminBadge.colorFor(s['status'] ?? ''))),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
        ),
        AdminPager(
          page: _page,
          hasMore: _hasMore,
          loading: _listLoading,
          onPageChange: (p) {
            setState(() => _page = p);
            _loadList(tab);
          },
        ),
      ]),
    );
  }

  // ── Plans tab ──
  Widget _plansTab() {
    if (_plansLoading) return const AdminTableSkeleton(columns: 7);
    if (_plans.isEmpty) return const AdminEmptyState();
    final maxSubs = _plans.fold<int>(
        1,
        (m, p) => (p['total_subscribers'] as int? ?? 0) > m
            ? p['total_subscribers'] as int
            : m);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AdminSectionCard(
          title: 'Subscribers by Plan',
          child: SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _plans.map((p) {
                final total = (p['total_subscribers'] as int?) ?? 0;
                final h = maxSubs == 0 ? 2.0 : (total / maxSubs) * 120 + 4;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$total',
                          style: const TextStyle(
                              fontSize: 11,
                              color: kAdminTextPri,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Tooltip(
                        message: '${p['display_name']}: $total subscribers',
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          height: h,
                          decoration: BoxDecoration(
                              color: total > 0 ? kAdminAccent : kAdminBorder,
                              borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(p['display_name'] ?? p['name'] ?? '',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10.5,
                              color: kAdminTextMuted,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          title: 'Plan Details',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(kAdminBg),
              columns: const [
                DataColumn(label: Text('Plan')),
                DataColumn(label: Text('Monthly')),
                DataColumn(label: Text('Yearly')),
                DataColumn(label: Text('Total')),
                DataColumn(label: Text('Active')),
                DataColumn(label: Text('Expired')),
                DataColumn(label: Text('Cancelled')),
                DataColumn(label: Text('Revenue')),
              ],
              rows: _plans.map((p) {
                return DataRow(cells: [
                  DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(p['display_name'] ?? p['name'] ?? ''),
                    const SizedBox(width: 6),
                    if (p['is_active'] != true)
                      const AdminBadge('inactive', kAdminTextMuted),
                  ])),
                  DataCell(Text(fmtRupees(p['price_monthly'] as num?))),
                  DataCell(Text(fmtRupees(p['price_yearly'] as num?))),
                  DataCell(Text('${p['total_subscribers'] ?? 0}')),
                  DataCell(Text('${p['active_subscribers'] ?? 0}',
                      style: const TextStyle(color: kAdminGreen))),
                  DataCell(Text('${p['expired_subscribers'] ?? 0}')),
                  DataCell(Text('${p['cancelled_subscribers'] ?? 0}',
                      style: const TextStyle(color: kAdminRed))),
                  DataCell(Text(fmtRupees(p['total_revenue'] as num?),
                      style: const TextStyle(fontWeight: FontWeight.w700))),
                ]);
              }).toList(),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Revenue tab ──
  Widget _revenueTab() {
    if (_revenueLoading) return const AdminLoader(topPadding: 40);
    final s = (_revenue['summary'] as Map<String, dynamic>?) ?? {};
    final trend = (_revenue['trend_30d'] as List?) ?? [];
    final maxV = trend.isEmpty
        ? 1.0
        : trend
            .map((d) => ((d['value'] as num?) ?? 0).toDouble())
            .reduce((a, b) => a > b ? a : b)
            .clamp(1, double.infinity);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AdminSectionCard(
          title: 'Revenue Summary',
          child: Wrap(spacing: 16, runSpacing: 16, children: [
            _revTile('Total Revenue', s['total_revenue'], kAdminGreen),
            _revTile("Today", s['today_revenue'], kAdminAccent),
            _revTile('Last 7 Days', s['last_7_days_revenue'], kAdminAccent),
            _revTile('Last 30 Days', s['last_30_days_revenue'], kAdminAccent),
            _revTile('This Month', s['this_month_revenue'], kAdminGold),
            _revTile('Last Month', s['last_month_revenue'], kAdminTextMuted),
            _revTile('Year to Date', s['year_to_date_revenue'],
                const Color(0xFF7C3AED)),
          ]),
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          title: 'Revenue — Last 30 Days',
          child: SizedBox(
            height: 120,
            child: trend.isEmpty
                ? const AdminEmptyState()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: trend.map((d) {
                      final v = ((d['value'] as num?) ?? 0).toDouble();
                      final h = (v / maxV) * 100 + 2;
                      return Expanded(
                        child: Tooltip(
                          message: '${d['date']}: ${fmtRupees(v)}',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              height: h,
                              decoration: BoxDecoration(
                                  color: v > 0 ? kAdminGreen : kAdminBorder,
                                  borderRadius: BorderRadius.circular(2)),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _revTile(String label, dynamic value, Color color) => SizedBox(
        width: 180,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fmtRupees(value as num?),
              style: TextStyle(
                  color: color, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: kAdminTextMuted, fontSize: 11.5)),
        ]),
      );

  // ── Payment History tab ──
  Widget _paymentsTab() {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AdminSearchField(
                hint: 'Search transaction, firm, owner…',
                onChanged: (v) {
                  _search = v;
                  _applyFilters();
                },
              ),
              for (final s in const [
                ('', 'All'),
                ('captured', 'Captured'),
                ('failed', 'Failed'),
                ('refunded', 'Refunded')
              ])
                AdminFilterChip(
                    label: s.$2,
                    selected: _paymentStatusFilter == s.$1,
                    onTap: () {
                      setState(() => _paymentStatusFilter = s.$1);
                      _applyFilters();
                    }),
              OutlinedButton.icon(
                  onPressed: () => _exportCsv('Payments', _payments),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('CSV')),
              OutlinedButton.icon(
                  onPressed: () => _exportPdf('Payments', _payments),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                  label: const Text('PDF')),
            ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 540,
          child: _paymentsLoading
              ? const AdminTableSkeleton(columns: 8)
              : _payments.isEmpty
                  ? const AdminEmptyState()
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(kAdminBg),
                          columns: const [
                            DataColumn(label: Text('Transaction ID')),
                            DataColumn(label: Text('User')),
                            DataColumn(label: Text('Email')),
                            DataColumn(label: Text('Plan')),
                            DataColumn(label: Text('Amount')),
                            DataColumn(label: Text('Gateway')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Date')),
                          ],
                          rows: _payments.map((p) {
                            return DataRow(
                              onSelectChanged: (_) => _showPaymentDetail(p),
                              cells: [
                                DataCell(Text(p['transaction_id'] ?? '-',
                                    style: const TextStyle(fontSize: 11.5))),
                                DataCell(Text(p['user_name'] ?? '-')),
                                DataCell(Text(p['user_email'] ?? '-',
                                    style: const TextStyle(
                                        color: kAdminTextMuted))),
                                DataCell(Text(p['plan_display_name'] ?? '-')),
                                DataCell(Text(fmtRupees(p['amount'] as num?),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700))),
                                DataCell(Text((p['payment_gateway'] ?? '-')
                                    .toString()
                                    .toUpperCase())),
                                DataCell(AdminBadge(p['status'] ?? '',
                                    AdminBadge.colorFor(p['status'] ?? ''))),
                                DataCell(Text(fmtDate(p['payment_date']))),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
        ),
        AdminPager(
          page: _paymentsPage,
          hasMore: _paymentsHasMore,
          loading: _paymentsLoading,
          onPageChange: (p) {
            setState(() => _paymentsPage = p);
            _loadPayments();
          },
        ),
      ]),
    );
  }

  void _showPaymentDetail(dynamic p) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Expanded(
                        child: Text('Payment Details',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800))),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded)),
                  ]),
                  AdminBadge(p['status'] ?? '',
                      AdminBadge.colorFor(p['status'] ?? '')),
                  const Divider(height: 24),
                  _dr('Transaction ID', p['transaction_id']),
                  _dr('Order ID', p['order_id']),
                  _dr('User', '${p['user_name']} (${p['user_role']})'),
                  _dr('Email', p['user_email']),
                  _dr('Plan', p['plan_display_name']),
                  _dr('Billing Cycle', p['billing_cycle']),
                  _dr('Gross Amount', fmtRupees(p['amount'] as num?)),
                  _dr('GST', _naIfNull(p['gst'])),
                  _dr('Platform Fee', _naIfNull(p['platform_fee'])),
                  _dr('Discount', _naIfNull(p['discount'])),
                  _dr('Final Amount', fmtRupees(p['final_amount'] as num?)),
                  _dr('Payment Method', _naIfNull(p['payment_method'])),
                  _dr('Payment Gateway',
                      (p['payment_gateway'] ?? '').toString().toUpperCase()),
                  _dr('Payment Date', fmtDate(p['payment_date'])),
                  const Divider(height: 24),
                  const Text('Refund',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12.5)),
                  const SizedBox(height: 8),
                  _dr('Refund Amount', _naIfNull(p['refund_amount'])),
                  _dr('Refund Status',
                      'Not applicable — subscription payments cannot be refunded'),
                ]),
          ),
        ),
      ),
    );
  }

  void _showDetail(String id) async {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 560,
          constraints: const BoxConstraints(maxHeight: 640),
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _repo
                .subscriptionDetail(id)
                .then((r) => (r['data'] as Map<String, dynamic>?) ?? {}),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()));
              }
              final d =
                  (snap.data!['subscription'] as Map<String, dynamic>?) ?? {};
              final payments = (snap.data!['payments'] as List?) ?? [];
              return SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(d['firm_name'] ?? 'Subscription',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800))),
                        IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded)),
                      ]),
                      Row(children: [
                        AdminBadge(d['status'] ?? '',
                            AdminBadge.colorFor(d['status'] ?? '')),
                      ]),
                      const Divider(height: 24),
                      const Text('User Details',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12.5)),
                      const SizedBox(height: 8),
                      _dr(
                          'Name',
                          (d['owner_name'] ?? '').toString().isEmpty
                              ? d['firm_name']
                              : d['owner_name']),
                      _dr(
                          'Email',
                          (d['owner_email'] ?? '').toString().isEmpty
                              ? d['firm_email']
                              : d['owner_email']),
                      _dr(
                          'Phone',
                          (d['owner_phone'] ?? '').toString().isEmpty
                              ? d['firm_phone']
                              : d['owner_phone']),
                      _dr('Role', 'Lawyer'),
                      const Divider(height: 24),
                      const Text('Subscription Details',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12.5)),
                      const SizedBox(height: 8),
                      _dr('Plan', d['plan_display_name']),
                      _dr('Price', fmtRupees(d['plan_price'] as num?)),
                      _dr('Billing Period', d['billing_cycle']),
                      _dr('Start Date', fmtDate(d['start_date'])),
                      _dr(
                          'Expiry Date',
                          fmtDate((d['current_period_end'] ?? '')
                                  .toString()
                                  .isNotEmpty
                              ? d['current_period_end']
                              : d['trial_ends_at'])),
                      _dr('Status',
                          (d['status'] ?? '').toString().toUpperCase()),
                      if ((d['cancelled_at'] ?? '').toString().isNotEmpty)
                        _dr('Cancelled At', fmtDate(d['cancelled_at'])),
                      const Divider(height: 24),
                      const Text('Payment History',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12.5)),
                      const SizedBox(height: 8),
                      if (payments.isEmpty)
                        const Text(
                            'No payments recorded for this subscription.',
                            style: TextStyle(
                                color: kAdminTextMuted, fontSize: 12.5))
                      else
                        ...payments.map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: kAdminBg,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _dr('Transaction ID',
                                          p['transaction_id']),
                                      _dr('Amount',
                                          fmtRupees(p['amount'] as num?)),
                                      _dr('Status', p['status']),
                                      _dr('Date', fmtDate(p['payment_date'])),
                                      _dr('GST / Platform Fee / Discount',
                                          'N/A'),
                                      _dr('Refund', 'Not applicable'),
                                    ]),
                              ),
                            )),
                    ]),
              );
            },
          ),
        ),
      ),
    );
  }

  String _naIfNull(dynamic v) => v == null ? 'N/A' : fmtRupees(v as num?);

  Widget _dr(String label, dynamic value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 140,
              child: Text(label,
                  style:
                      const TextStyle(color: kAdminTextMuted, fontSize: 12))),
          Expanded(
              child: SelectableText('${value ?? '-'}',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: kAdminTextPri))),
        ]),
      );

  // ── Export ──
  List<List<String>> _rowsToTable(String tab, List<dynamic> rows) {
    if (tab == 'Payments') {
      return [
        [
          'Transaction ID',
          'User',
          'Email',
          'Plan',
          'Amount',
          'Gateway',
          'Status',
          'Date'
        ],
        ...rows.map((p) => [
              '${p['transaction_id'] ?? ''}',
              '${p['user_name'] ?? ''}',
              '${p['user_email'] ?? ''}',
              '${p['plan_display_name'] ?? ''}',
              fmtRupees(p['amount'] as num?),
              '${p['payment_gateway'] ?? ''}',
              '${p['status'] ?? ''}',
              fmtDate(p['payment_date']),
            ]),
      ];
    }
    return [
      [
        'Firm/Owner',
        'Email',
        'Role',
        'Plan',
        'Price',
        'Start Date',
        'Expiry Date',
        'Days Left',
        'Payment Status',
        'Status'
      ],
      ...rows.map((s) {
        final name = (s['owner_name'] ?? '').toString().isNotEmpty
            ? s['owner_name']
            : s['firm_name'] ?? '';
        final email = (s['owner_email'] ?? '').toString().isNotEmpty
            ? s['owner_email']
            : s['firm_email'] ?? '';
        return [
          '$name',
          '$email',
          'Lawyer',
          '${s['plan_display_name'] ?? ''}',
          fmtRupees(s['plan_price'] as num?),
          fmtDate(s['start_date']),
          fmtDate((s['current_period_end'] ?? '').toString().isNotEmpty
              ? s['current_period_end']
              : s['trial_ends_at']),
          '${s['days_remaining'] ?? ''}',
          '${s['payment_status'] ?? ''}',
          '${s['status'] ?? ''}',
        ];
      }),
    ];
  }

  void _exportCsv(String tab, List<dynamic> rows) {
    final table = _rowsToTable(tab, rows);
    final csv = table
        .map((row) => row.map((cell) {
              final escaped = cell.replaceAll('"', '""');
              return escaped.contains(',') ||
                      escaped.contains('"') ||
                      escaped.contains('\n')
                  ? '"$escaped"'
                  : escaped;
            }).join(','))
        .join('\r\n');
    final bytes = Uint8List.fromList(csv.codeUnits);
    final ok = triggerBrowserDownload(
        bytes, 'libra_subscriptions_$tab.csv', 'text/csv');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('CSV export is only available in the Chrome admin panel.')));
    }
  }

  Future<void> _exportPdf(String tab, List<dynamic> rows) async {
    final table = _rowsToTable(tab, rows);
    final doc = pw.Document();
    final now = DateFormat('d MMM yyyy, h:mm a').format(DateTime.now());
    final rangeLabel = _dateRange == null
        ? 'All time'
        : '${DateFormat('d MMM yyyy').format(_dateRange!.start)} – ${DateFormat('d MMM yyyy').format(_dateRange!.end)}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('LIBRA LAW',
                          style: pw.TextStyle(
                              fontSize: 20, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Super Admin — Subscriptions Report',
                          style: const pw.TextStyle(fontSize: 12)),
                    ]),
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Generated: $now',
                          style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('Range: $rangeLabel',
                          style: const pw.TextStyle(fontSize: 9)),
                    ]),
              ]),
          pw.SizedBox(height: 6),
          pw.Text('Section: $tab (${rows.length} records)',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          pw.Text('Summary',
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Bullet(text: 'Total subscriptions: ${_n('total_subscriptions')}'),
          pw.Bullet(
              text: 'Active subscriptions: ${_n('active_subscriptions')}'),
          pw.Bullet(text: 'Premium users: ${_n('premium_users')}'),
          pw.Bullet(
              text: 'Expired subscriptions: ${_n('expired_subscriptions')}'),
          pw.Bullet(
              text:
                  'Cancelled subscriptions: ${_n('cancelled_subscriptions')}'),
          pw.Bullet(
              text:
                  'Total subscription revenue: ${fmtRupees(_n('total_revenue'))}'),
          pw.SizedBox(height: 10),
          pw.Text('Plan-wise Statistics',
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.TableHelper.fromTextArray(
            headers: [
              'Plan',
              'Monthly',
              'Total',
              'Active',
              'Expired',
              'Cancelled',
              'Revenue'
            ],
            data: _plans
                .map((p) => [
                      '${p['display_name'] ?? p['name'] ?? ''}',
                      fmtRupees(p['price_monthly'] as num?),
                      '${p['total_subscribers'] ?? 0}',
                      '${p['active_subscribers'] ?? 0}',
                      '${p['expired_subscribers'] ?? 0}',
                      '${p['cancelled_subscribers'] ?? 0}',
                      fmtRupees(p['total_revenue'] as num?),
                    ])
                .toList(),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 14),
          pw.Text('Detailed Records — $tab',
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: table.first,
            data: table.skip(1).toList(),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final ok = triggerBrowserDownload(
        bytes, 'libra_subscriptions_$tab.pdf', 'application/pdf');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('PDF export is only available in the Chrome admin panel.')));
    }
  }
}
