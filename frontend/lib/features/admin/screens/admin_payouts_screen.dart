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

/// Super Admin → Payouts & Settlements.
///
/// UI-only redesign (premium KPI cards, an earnings-overview chart, a
/// payment breakdown panel, a nicer settlement table) — every data source,
/// repository call, and the underlying pending/paid/settlement calculation
/// is untouched. No commission/payout system existed anywhere in this app
/// before the backend module this screen talks to (see
/// admin_payouts_controller.go's file header): a consultation payment was
/// booked 100% as lawyer earnings the instant a client paid, with no
/// platform commission or GST ever deducted. Every commission/GST figure
/// here is therefore a genuine ₹0 — reused exactly as the API returns it —
/// and "pending" vs "paid" reflects a real settlement record a Super Admin
/// creates when they actually pay a lawyer.
class AdminPayoutsScreen extends StatefulWidget {
  const AdminPayoutsScreen({super.key});
  @override
  State<AdminPayoutsScreen> createState() => _AdminPayoutsScreenState();
}

enum _TrendPeriod { today, days7, days30, thisMonth, thisYear }

class _AdminPayoutsScreenState extends State<AdminPayoutsScreen>
    with SingleTickerProviderStateMixin {
  final _repo = AdminRepository();
  late TabController _tabCtrl;

  bool _statsLoading = true;
  Map<String, dynamic> _stats = {};
  String? _statsError;

  bool _trendsLoading = true;
  Map<String, dynamic> _trends = {};
  _TrendPeriod _trendPeriod = _TrendPeriod.days30;

  bool _lawyersLoading = true;
  List<dynamic> _lawyers = [];
  int _lawyersPage = 1;
  bool _lawyersHasMore = false;
  String _lawyerSearch = '';
  String _lawyerStatusFilter = '';

  bool _pendingLoading = true;
  List<dynamic> _pending = [];

  bool _paidLoading = true;
  List<dynamic> _paid = [];
  int _paidPage = 1;
  bool _paidHasMore = false;

  bool _settlementsLoading = true;
  List<dynamic> _settlements = [];
  int _settlementsPage = 1;
  bool _settlementsHasMore = false;
  String _settlementStatusFilter = '';

  String _search = '';
  DateTimeRange? _dateRange;

  static const _tabs = [
    'Lawyer Earnings',
    'Pending Payouts',
    'Paid Payouts',
    'Settlement History'
  ];
  static const _tabIcons = [
    Icons.people_alt_rounded,
    Icons.hourglass_bottom_rounded,
    Icons.check_circle_rounded,
    Icons.receipt_long_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) _loadForCurrentTab(silent: false);
    });
    _loadStats();
    _loadTrends();
    _loadForCurrentTab(silent: false);
    AutoRefreshService.instance.register('admin_payouts', () async {
      await Future.wait([
        _loadStats(silent: true),
        _loadTrends(silent: true),
        _loadForCurrentTab(silent: true),
      ]);
    });
  }

  @override
  void dispose() {
    AutoRefreshService.instance.unregister('admin_payouts');
    _tabCtrl.dispose();
    super.dispose();
  }

  String? get _fromStr => _dateRange != null
      ? DateFormat('yyyy-MM-dd').format(_dateRange!.start)
      : null;
  String? get _toStr => _dateRange != null
      ? DateFormat('yyyy-MM-dd').format(_dateRange!.end)
      : null;

  int get _trendDays {
    final now = DateTime.now();
    switch (_trendPeriod) {
      case _TrendPeriod.today:
        return 1;
      case _TrendPeriod.days7:
        return 7;
      case _TrendPeriod.days30:
        return 30;
      case _TrendPeriod.thisMonth:
        return now.day;
      case _TrendPeriod.thisYear:
        // The backend clamps the trend window to 180 days — this reuses that
        // existing limit rather than requesting an unsupported range.
        final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
        return dayOfYear > 180 ? 180 : dayOfYear;
    }
  }

  Future<void> _loadStats({bool silent = false}) async {
    if (!silent) setState(() => _statsLoading = true);
    try {
      final res = await _repo.payoutStats();
      if (!mounted) return;
      setState(() {
        _stats = (res['data'] as Map<String, dynamic>?) ?? {};
        _statsLoading = false;
        _statsError = null;
      });
    } on AdminException catch (e) {
      if (!silent && mounted)
        setState(() {
          _statsLoading = false;
          _statsError = e.message;
        });
    }
  }

  Future<void> _loadTrends({bool silent = false}) async {
    if (!silent) setState(() => _trendsLoading = true);
    try {
      final res = await _repo.payoutTrends(days: _trendDays, to: _toStr);
      if (!mounted) return;
      setState(() {
        _trends = (res['data'] as Map<String, dynamic>?) ?? {};
        _trendsLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _trendsLoading = false);
    }
  }

  Future<void> _loadForCurrentTab({required bool silent}) async {
    switch (_tabs[_tabCtrl.index]) {
      case 'Lawyer Earnings':
        await _loadLawyers(silent: silent);
        break;
      case 'Pending Payouts':
        await _loadPending(silent: silent);
        break;
      case 'Paid Payouts':
        await _loadPaid(silent: silent);
        break;
      case 'Settlement History':
        await _loadSettlements(silent: silent);
        break;
    }
  }

  Future<void> _loadLawyers({bool silent = false}) async {
    if (!silent) setState(() => _lawyersLoading = true);
    try {
      final res = await _repo.payoutLawyers(
          search: _lawyerSearch,
          status: _lawyerStatusFilter,
          page: _lawyersPage);
      if (!mounted) return;
      setState(() {
        _lawyers = (res['data'] as List?) ?? [];
        _lawyersHasMore = (res['meta']?['has_more'] as bool?) ?? false;
        _lawyersLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _lawyersLoading = false);
    }
  }

  Future<void> _loadPending({bool silent = false}) async {
    if (!silent) setState(() => _pendingLoading = true);
    try {
      final res = await _repo.pendingPayouts(search: _search);
      if (!mounted) return;
      setState(() {
        _pending = (res['data'] as List?) ?? [];
        _pendingLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _pendingLoading = false);
    }
  }

  Future<void> _loadPaid({bool silent = false}) async {
    if (!silent) setState(() => _paidLoading = true);
    try {
      final res = await _repo.paidPayouts(
          search: _search, from: _fromStr, to: _toStr, page: _paidPage);
      if (!mounted) return;
      setState(() {
        _paid = (res['data'] as List?) ?? [];
        _paidHasMore = (res['meta']?['has_more'] as bool?) ?? false;
        _paidLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _paidLoading = false);
    }
  }

  Future<void> _loadSettlements({bool silent = false}) async {
    if (!silent) setState(() => _settlementsLoading = true);
    try {
      final res = await _repo.settlements(
          status: _settlementStatusFilter,
          search: _search,
          from: _fromStr,
          to: _toStr,
          page: _settlementsPage);
      if (!mounted) return;
      setState(() {
        _settlements = (res['data'] as List?) ?? [];
        _settlementsHasMore = (res['meta']?['has_more'] as bool?) ?? false;
        _settlementsLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _settlementsLoading = false);
    }
  }

  void _refreshAll() {
    _loadStats();
    _loadTrends();
    _loadForCurrentTab(silent: false);
  }

  void _applyFilters() {
    _lawyersPage = 1;
    _paidPage = 1;
    _settlementsPage = 1;
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
      _loadTrends();
      _applyFilters();
    }
  }

  num _n(String key) => (_stats[key] as num?) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/payouts',
      title: 'Payouts & Settlements',
      actions: [
        _HeaderIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onTap: _refreshAll),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _pageHeader(),
        const SizedBox(height: 22),
        _kpiGrid(),
        const SizedBox(height: 22),
        LayoutBuilder(builder: (context, constraints) {
          final stacked = constraints.maxWidth < 980;
          final chart = _earningsOverviewCard();
          final breakdown = _paymentBreakdownCard();
          if (stacked) {
            return Column(
                children: [chart, const SizedBox(height: 16), breakdown]);
          }
          return IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 2, child: chart),
              const SizedBox(width: 16),
              Expanded(child: breakdown),
            ]),
          );
        }),
        const SizedBox(height: 22),
        _tableSection(),
      ]),
    );
  }

  // ── Header: title/subtitle, date range, export ──
  Widget _pageHeader() {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      final titleBlock =
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Payouts & Settlements',
            style: TextStyle(
                color: kAdminTextPri,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3)),
        const SizedBox(height: 4),
        const Text(
            'Track lawyer earnings, platform commission, GST and settlement history',
            style: TextStyle(color: kAdminTextMuted, fontSize: 12.5)),
      ]);
      final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _dateRangeButton(),
            _ExportButton(
              icon: Icons.download_rounded,
              label: 'CSV',
              onTap: () => _exportCsv(_currentTabExportKey, _currentTabRows),
            ),
            _ExportButton(
              icon: Icons.picture_as_pdf_rounded,
              label: 'PDF',
              onTap: () => _exportPdf(_tabs[_tabCtrl.index], _currentTabRows),
            ),
          ]);
      if (compact) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleBlock, const SizedBox(height: 14), actions]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        actions,
      ]);
    });
  }

  Widget _dateRangeButton() => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _pickDateRange,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: _dateRange != null
                  ? kAdminAccent.withValues(alpha: 0.08)
                  : kAdminCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _dateRange != null ? kAdminAccent : kAdminBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.date_range_rounded,
                  size: 16,
                  color: _dateRange != null ? kAdminAccent : kAdminTextMuted),
              const SizedBox(width: 7),
              Text(
                  _dateRange == null
                      ? 'Date range'
                      : '${DateFormat('d MMM').format(_dateRange!.start)} – ${DateFormat('d MMM').format(_dateRange!.end)}',
                  style: TextStyle(
                      color: _dateRange != null ? kAdminAccent : kAdminTextPri,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
              if (_dateRange != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    setState(() => _dateRange = null);
                    _loadTrends();
                    _applyFilters();
                  },
                  child: const Icon(Icons.close_rounded,
                      size: 14, color: kAdminAccent),
                ),
              ],
            ]),
          ),
        ),
      );

  String get _currentTabExportKey {
    switch (_tabs[_tabCtrl.index]) {
      case 'Lawyer Earnings':
        return 'LawyerEarnings';
      case 'Paid Payouts':
        return 'PaidPayouts';
      default:
        return 'Settlements';
    }
  }

  List<dynamic> get _currentTabRows {
    switch (_tabs[_tabCtrl.index]) {
      case 'Lawyer Earnings':
        return _lawyers;
      case 'Pending Payouts':
        return _pending;
      case 'Paid Payouts':
        return _paid;
      default:
        return _settlements;
    }
  }

  // ── KPI cards ──
  Widget _kpiGrid() {
    if (_statsLoading) return const AdminStatGridSkeleton(count: 8);
    if (_statsError != null)
      return _ErrorBanner(message: _statsError!, onRetry: () => _loadStats());
    final f =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final cards = [
      _KpiSpec('Total Lawyer Earnings', f.format(_n('total_lawyer_earnings')),
          Icons.savings_rounded, kAdminAccent, 0),
      _KpiSpec('Platform Commission', f.format(_n('total_platform_commission')),
          Icons.percent_rounded, const Color(0xFF7C3AED), null),
      _KpiSpec('Total GST', f.format(_n('total_gst')),
          Icons.receipt_long_rounded, kAdminAmber, null),
      _KpiSpec('Net Lawyer Payout', f.format(_n('total_net_lawyer_payout')),
          Icons.account_balance_wallet_rounded, kAdminGreen, 0),
      _KpiSpec('Pending Payout', f.format(_n('pending_payout')),
          Icons.hourglass_bottom_rounded, kAdminAmber, 1),
      _KpiSpec('Paid Payout', f.format(_n('paid_payout')),
          Icons.check_circle_rounded, kAdminGreen, 2),
      _KpiSpec('Lawyers Awaiting Payout', '${_n('lawyers_awaiting_payout')}',
          Icons.people_alt_rounded, const Color(0xFFDB2777), 1),
      _KpiSpec('Completed Settlements', '${_n('completed_settlements')}',
          Icons.fact_check_rounded, kAdminAccent, 3),
    ];
    return AdminStatGrid(
      mainAxisExtent: 92,
      cards: cards.asMap().entries.map((e) {
        final i = e.key;
        final c = e.value;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 180 + i * 25),
          curve: Curves.easeOut,
          builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                  offset: Offset(0, 8 * (1 - v)), child: child)),
          child: _KpiCard(
              spec: c,
              onTap: c.tabIndex == null
                  ? null
                  : () => _tabCtrl.animateTo(c.tabIndex!)),
        );
      }).toList(),
    );
  }

  // ── Earnings Overview chart ──
  Widget _earningsOverviewCard() {
    final series = <_ChartSeries>[
      _ChartSeries('Lawyer Earnings', kAdminAccent,
          (_trends['lawyer_earnings'] as List?) ?? []),
      _ChartSeries('Platform Commission', const Color(0xFF7C3AED),
          (_trends['platform_commission'] as List?) ?? []),
      _ChartSeries('GST', kAdminAmber, (_trends['gst'] as List?) ?? []),
      _ChartSeries('Net Lawyer Payout', kAdminGreen,
          (_trends['net_lawyer_payouts'] as List?) ?? []),
    ];
    final hasData = series
        .any((s) => s.points.any((p) => ((p['value'] as num?) ?? 0) != 0));

    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 480;
          final title = Row(children: [
            Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                    color: kAdminAccent,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            const Text('Earnings Overview',
                style: TextStyle(
                    color: kAdminTextPri,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
          ]);
          final selector = _periodSelector();
          if (compact) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 10), selector]);
          }
          return Row(children: [Expanded(child: title), selector]);
        }),
        const SizedBox(height: 16),
        if (_trendsLoading)
          const SizedBox(height: 220, child: AdminLoader(topPadding: 70))
        else if (!hasData)
          const SizedBox(
            height: 220,
            child: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.show_chart_rounded,
                        size: 36, color: kAdminTextMuted),
                    SizedBox(height: 10),
                    Text('No historical payout data available',
                        style: TextStyle(color: kAdminTextMuted, fontSize: 13)),
                  ]),
            ),
          )
        else ...[
          TweenAnimationBuilder<double>(
            key: ValueKey('${_trendPeriod}_${_trends.hashCode}'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            builder: (_, v, __) => Opacity(
              opacity: v,
              child: SizedBox(
                  height: 220,
                  child: _MultiLineChart(series: series, progress: v)),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
              spacing: 16,
              runSpacing: 8,
              children:
                  series.map((s) => _legendDot(s.label, s.color)).toList()),
        ],
      ]),
    );
  }

  Widget _periodSelector() {
    final options = [
      (_TrendPeriod.today, 'Today'),
      (_TrendPeriod.days7, '7D'),
      (_TrendPeriod.days30, '30D'),
      (_TrendPeriod.thisMonth, 'This Month'),
      (_TrendPeriod.thisYear, 'This Year'),
    ];
    return Wrap(
      spacing: 6,
      children: options
          .map((o) => AdminFilterChip(
                label: o.$2,
                selected: _trendPeriod == o.$1,
                onTap: () {
                  setState(() => _trendPeriod = o.$1);
                  _loadTrends();
                },
              ))
          .toList(),
    );
  }

  Widget _legendDot(String label, Color color) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                color: kAdminTextMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600)),
      ]);

  // ── Payment breakdown ──
  Widget _paymentBreakdownCard() {
    final segments = <(String, num, Color)>[
      ('Net Lawyer Payout', _n('total_net_lawyer_payout'), kAdminGreen),
      (
        'Platform Commission',
        _n('total_platform_commission'),
        const Color(0xFF7C3AED)
      ),
      ('GST', _n('total_gst'), kAdminAmber),
    ];
    final total = segments.fold<num>(0, (a, s) => a + s.$2);
    final f =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return AdminSectionCard(
      title: 'Payment Breakdown',
      child: _statsLoading
          ? const SizedBox(height: 180, child: AdminLoader(topPadding: 60))
          : total <= 0
              ? const SizedBox(
                  height: 180,
                  child: Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.pie_chart_outline_rounded,
                              size: 34, color: kAdminTextMuted),
                          SizedBox(height: 10),
                          Text('No payout data available',
                              style: TextStyle(
                                  color: kAdminTextMuted, fontSize: 13)),
                        ]),
                  ),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 14,
                      child: Row(
                        children: segments.map((s) {
                          final frac =
                              total == 0 ? 0.0 : (s.$2 / total).toDouble();
                          if (frac <= 0) return const SizedBox.shrink();
                          return Expanded(
                            flex: (frac * 1000).round().clamp(1, 1000),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 500),
                              builder: (_, v, __) => Container(
                                  color:
                                      s.$3.withValues(alpha: 0.35 + 0.65 * v)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ...segments.map((s) {
                    final pct = total == 0 ? 0.0 : (s.$2 / total * 100);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: s.$3,
                                borderRadius: BorderRadius.circular(3))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(s.$1,
                                style: const TextStyle(
                                    color: kAdminTextPri,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600))),
                        Text(f.format(s.$2),
                            style: const TextStyle(
                                color: kAdminTextPri,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: 42,
                            child: Text('${pct.toStringAsFixed(0)}%',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    color: kAdminTextMuted, fontSize: 11.5))),
                      ]),
                    );
                  }),
                ]),
    );
  }

  // ── Table section with tabs, filters ──
  Widget _tableSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          tabs: List.generate(
              _tabs.length,
              (i) => Tab(
                  icon: Icon(_tabIcons[i], size: 16),
                  text: _tabs[i],
                  iconMargin: const EdgeInsets.only(bottom: 4))),
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 640,
        child: TabBarView(controller: _tabCtrl, children: [
          _lawyersTab(),
          _pendingTab(),
          _paidTab(),
          _settlementsTab(),
        ]),
      ),
    ]);
  }

  Widget _filterBar(List<Widget> children) => Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children);

  // ── Lawyer-wise earnings tab ──
  Widget _lawyersTab() {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _filterBar([
          AdminSearchField(
            hint: 'Search lawyer name or email…',
            onChanged: (v) {
              _lawyerSearch = v;
              _applyFilters();
            },
          ),
          for (final s in const [
            ('', 'All'),
            ('pending', 'Pending'),
            ('settled', 'Settled')
          ])
            AdminFilterChip(
                label: s.$2,
                selected: _lawyerStatusFilter == s.$1,
                onTap: () {
                  setState(() => _lawyerStatusFilter = s.$1);
                  _applyFilters();
                }),
          _HeaderIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh',
              onTap: () => _loadLawyers()),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 460,
          child: _lawyersLoading
              ? const AdminTableSkeleton(columns: 10)
              : _lawyers.isEmpty
                  ? const AdminEmptyState(message: 'No lawyer earnings found')
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          dataRowMinHeight: 46,
                          dataRowMaxHeight: 52,
                          headingRowColor: WidgetStateProperty.all(kAdminBg),
                          columns: const [
                            DataColumn(label: Text('Lawyer')),
                            DataColumn(label: Text('Email')),
                            DataColumn(label: Text('Consultations')),
                            DataColumn(label: Text('Gross Earnings')),
                            DataColumn(label: Text('Commission')),
                            DataColumn(label: Text('GST')),
                            DataColumn(label: Text('Net Payout')),
                            DataColumn(label: Text('Pending')),
                            DataColumn(label: Text('Paid')),
                            DataColumn(label: Text('Last Payout')),
                            DataColumn(label: Text('Status')),
                          ],
                          rows: _lawyers.map((l) {
                            return DataRow(
                              onSelectChanged: (_) =>
                                  _showLawyerDetail(l['id']),
                              cells: [
                                DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _Avatar(name: l['name'] ?? '?'),
                                      const SizedBox(width: 8),
                                      Text(l['name'] ?? '-'),
                                    ])),
                                DataCell(Text(l['email'] ?? '-',
                                    style: const TextStyle(
                                        color: kAdminTextMuted))),
                                DataCell(
                                    Text('${l['total_consultations'] ?? 0}')),
                                DataCell(Text(
                                    fmtRupees(l['gross_earnings'] as num?),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700))),
                                DataCell(Text(fmtRupees(
                                    l['platform_commission'] as num?))),
                                DataCell(Text(fmtRupees(l['gst'] as num?))),
                                DataCell(Text(
                                    fmtRupees(l['net_payout'] as num?),
                                    style:
                                        const TextStyle(color: kAdminGreen))),
                                DataCell(Text(
                                    fmtRupees(l['pending_amount'] as num?),
                                    style: TextStyle(
                                        color:
                                            (l['pending_amount'] as num? ?? 0) >
                                                    0
                                                ? kAdminAmber
                                                : kAdminTextMuted))),
                                DataCell(
                                    Text(fmtRupees(l['paid_amount'] as num?))),
                                DataCell(Text(l['last_payout_date'] == null
                                    ? 'N/A'
                                    : fmtDate(l['last_payout_date']))),
                                DataCell(AdminBadge(
                                    l['payout_status'] ?? '',
                                    AdminBadge.colorFor(
                                        l['payout_status'] ?? ''))),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
        ),
        AdminPager(
          page: _lawyersPage,
          hasMore: _lawyersHasMore,
          loading: _lawyersLoading,
          onPageChange: (p) {
            setState(() => _lawyersPage = p);
            _loadLawyers();
          },
        ),
      ]),
    );
  }

  void _showLawyerDetail(String id) {
    showDialog(
      context: context,
      // A dialog is inserted into the root Navigator's overlay, outside
      // AdminShell's scoped light Theme — so without this it silently
      // inherits the mobile app's global dark theme (see buildAdminTheme's
      // doc comment) and every explicitly-navy Text style in this modal
      // renders on a near-black Material surface instead of white,
      // reproducing exactly the "text is nearly invisible" bug. Wrapping in
      // the same admin Theme, plus an explicit white background on the
      // Dialog itself, fixes the actual cause rather than restyling text
      // that was already the correct color.
      builder: (dialogContext) => Theme(
        data: buildAdminTheme(dialogContext),
        child: Dialog(
          backgroundColor: kAdminCard,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660, maxHeight: 720),
            child: Container(
              padding: const EdgeInsets.all(24),
              child: FutureBuilder<Map<String, dynamic>>(
                future: _repo
                    .payoutLawyerDetail(id)
                    .then((r) => (r['data'] as Map<String, dynamic>?) ?? {}),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _DialogError(
                        message: 'Failed to load lawyer detail.',
                        onClose: () => Navigator.pop(context));
                  }
                  if (!snap.hasData) {
                    return const SizedBox(
                        height: 220,
                        child: Center(
                            child:
                                CircularProgressIndicator(strokeWidth: 2.4)));
                  }
                  final lawyer =
                      (snap.data!['lawyer'] as Map<String, dynamic>?) ?? {};
                  final summary =
                      (snap.data!['summary'] as Map<String, dynamic>?) ?? {};
                  final txns = (snap.data!['transactions'] as List?) ?? [];
                  return SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            _Avatar(name: lawyer['name'] ?? '?', size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(lawyer['name'] ?? 'Lawyer',
                                      style: const TextStyle(
                                          color: kAdminTextPri,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800)),
                                  Text(lawyer['email'] ?? '',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: kAdminTextMuted)),
                                ])),
                            if ((summary['total_pending'] as num? ?? 0) > 0)
                              FilledButton.icon(
                                onPressed: () =>
                                    _createSettlement(id, lawyer['name'] ?? ''),
                                icon: const Icon(Icons.payments_rounded,
                                    size: 16),
                                label: const Text('Mark Pending as Paid'),
                              ),
                            IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded,
                                    color: kAdminTextPri)),
                          ]),
                          const Divider(height: 28),
                          _sectionLabel('Lawyer Details'),
                          const SizedBox(height: 10),
                          _dr(
                              'Phone',
                              (lawyer['phone'] ?? '').toString().isEmpty
                                  ? 'N/A'
                                  : lawyer['phone']),
                          _dr('Lawyer ID', lawyer['id']),
                          _dr(
                              'Verification Status',
                              (lawyer['verification_status'] ?? '')
                                      .toString()
                                      .isEmpty
                                  ? 'N/A'
                                  : lawyer['verification_status']),
                          const Divider(height: 28),
                          _sectionLabel('Earnings Summary'),
                          const SizedBox(height: 12),
                          Wrap(spacing: 24, runSpacing: 12, children: [
                            _summaryStat(
                                'Consultations',
                                '${summary['total_consultations'] ?? 0}',
                                kAdminAccent),
                            _summaryStat(
                                'Gross Earnings',
                                fmtRupees(summary['gross_earnings'] as num?),
                                kAdminTextPri),
                            _summaryStat(
                                'Commission',
                                fmtRupees(
                                    summary['platform_commission'] as num?),
                                const Color(0xFF7C3AED)),
                            _summaryStat('GST',
                                fmtRupees(summary['gst'] as num?), kAdminAmber),
                            _summaryStat(
                                'Net Earnings',
                                fmtRupees(summary['net_earnings'] as num?),
                                kAdminGreen),
                            _summaryStat(
                                'Paid',
                                fmtRupees(summary['total_paid'] as num?),
                                kAdminGreen),
                            _summaryStat(
                                'Pending',
                                fmtRupees(summary['total_pending'] as num?),
                                kAdminAmber),
                          ]),
                          const Divider(height: 28),
                          _sectionLabel('Transaction Breakdown'),
                          const SizedBox(height: 10),
                          if (txns.isEmpty)
                            const Text(
                                'No consultation earnings for this lawyer yet.',
                                style: TextStyle(
                                    color: kAdminTextMuted, fontSize: 12.5))
                          else
                            ...txns.map((t) => _txnCard(t)),
                        ]),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _txnCard(dynamic t) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: kAdminBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kAdminBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(t['client_name'] ?? '-',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: kAdminTextPri))),
            AdminBadge(t['payout_status'] ?? '',
                AdminBadge.colorFor(t['payout_status'] ?? '')),
          ]),
          const SizedBox(height: 8),
          _dr('Consultation ID', t['consultation_id']),
          _dr('Service Type', t['service_type']),
          _dr('Date', '${t['date']} ${t['time'] ?? ''}'),
          _dr('Duration',
              '${((t['duration_seconds'] as int? ?? 0) / 60).round()} min'),
          _dr('Gross Amount', fmtRupees(t['gross_amount'] as num?)),
          _dr('Commission', fmtRupees(t['platform_commission'] as num?)),
          _dr('GST', fmtRupees(t['gst'] as num?)),
          _dr('Lawyer Earning', fmtRupees(t['lawyer_earning'] as num?)),
          _dr('Payout Date',
              t['payout_date'] == null ? 'Pending' : fmtDate(t['payout_date'])),
        ]),
      );

  Widget _summaryStat(String label, String value, Color color) => SizedBox(
        width: 140,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: kAdminTextMuted, fontSize: 11)),
        ]),
      );

  Widget _sectionLabel(String s) => Row(children: [
        Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
                color: kAdminAccent, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(s,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: kAdminTextPri)),
      ]);

  Future<void> _createSettlement(String lawyerId, String lawyerName) async {
    final methodCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Settle payout for $lawyerName'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'This records that you have paid this lawyer their entire currently pending amount. Enter the real payment method and reference used (leave blank if unknown).',
              style: TextStyle(fontSize: 12.5, color: kAdminTextMuted)),
          const SizedBox(height: 16),
          TextField(
              controller: methodCtrl,
              decoration: const InputDecoration(
                  labelText: 'Payment Method (e.g. Bank Transfer)')),
          const SizedBox(height: 10),
          TextField(
              controller: refCtrl,
              decoration: const InputDecoration(labelText: 'Reference / UTR')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm Payout')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.createSettlement(
          lawyerId: lawyerId,
          paymentMethod: methodCtrl.text,
          reference: refCtrl.text);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settlement recorded.')));
      _loadStats();
      _loadForCurrentTab(silent: false);
    } on AdminException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ── Pending payouts tab ──
  Widget _pendingTab() {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _filterBar([
          AdminSearchField(
            hint: 'Search lawyer…',
            onChanged: (v) {
              _search = v;
              _loadPending();
            },
          ),
          _HeaderIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh',
              onTap: () => _loadPending()),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 460,
          child: _pendingLoading
              ? const AdminTableSkeleton(columns: 6)
              : _pending.isEmpty
                  ? const AdminEmptyState(
                      message: 'No pending payouts — every lawyer is settled')
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          dataRowMinHeight: 46,
                          dataRowMaxHeight: 56,
                          headingRowColor: WidgetStateProperty.all(kAdminBg),
                          columns: const [
                            DataColumn(label: Text('Lawyer')),
                            DataColumn(label: Text('Transactions')),
                            DataColumn(label: Text('Pending Amount')),
                            DataColumn(label: Text('Oldest Pending')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Action')),
                          ],
                          rows: _pending.map((p) {
                            return DataRow(
                              onSelectChanged: (_) =>
                                  _showLawyerDetail(p['lawyer_id']),
                              cells: [
                                DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _Avatar(name: p['lawyer_name'] ?? '?'),
                                      const SizedBox(width: 8),
                                      Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(p['lawyer_name'] ?? '-'),
                                            Text(p['lawyer_email'] ?? '',
                                                style: const TextStyle(
                                                    color: kAdminTextMuted,
                                                    fontSize: 11)),
                                          ]),
                                    ])),
                                DataCell(
                                    Text('${p['transaction_count'] ?? 0}')),
                                DataCell(Text(
                                    fmtRupees(p['pending_amount'] as num?),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: kAdminAmber))),
                                DataCell(Text(
                                    fmtDate(p['oldest_pending_transaction']))),
                                const DataCell(
                                    AdminBadge('pending', kAdminAmber)),
                                DataCell(TextButton.icon(
                                  onPressed: () => _createSettlement(
                                      p['lawyer_id'], p['lawyer_name'] ?? ''),
                                  icon: const Icon(Icons.payments_rounded,
                                      size: 15),
                                  label: const Text('Pay Now'),
                                )),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }

  // ── Paid payouts tab ──
  Widget _paidTab() {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _filterBar([
          AdminSearchField(
            hint: 'Search lawyer, reference…',
            onChanged: (v) {
              _search = v;
              _applyFilters();
            },
          ),
          _HeaderIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh',
              onTap: () => _loadPaid()),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 460,
          child: _paidLoading
              ? const AdminTableSkeleton(columns: 7)
              : _paid.isEmpty
                  ? const AdminEmptyState(message: 'No paid payouts yet')
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          dataRowMinHeight: 46,
                          dataRowMaxHeight: 52,
                          headingRowColor: WidgetStateProperty.all(kAdminBg),
                          columns: const [
                            DataColumn(label: Text('Lawyer')),
                            DataColumn(label: Text('Payout Amount')),
                            DataColumn(label: Text('Settlement ID')),
                            DataColumn(label: Text('Transactions')),
                            DataColumn(label: Text('Payout Date')),
                            DataColumn(label: Text('Method')),
                            DataColumn(label: Text('Reference')),
                          ],
                          rows: _paid.map((p) {
                            return DataRow(
                              onSelectChanged: (_) =>
                                  _showSettlementDetail(p['settlement_id']),
                              cells: [
                                DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _Avatar(name: p['lawyer_name'] ?? '?'),
                                      const SizedBox(width: 8),
                                      Text(p['lawyer_name'] ?? '-'),
                                    ])),
                                DataCell(Text(
                                    fmtRupees(p['payout_amount'] as num?),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: kAdminGreen))),
                                DataCell(Text(
                                    '${p['settlement_id']}'.substring(0, 8),
                                    style: const TextStyle(fontSize: 11))),
                                DataCell(
                                    Text('${p['transaction_count'] ?? 0}')),
                                DataCell(Text(fmtDate(p['payout_date']))),
                                DataCell(Text(p['payment_method'] ?? 'N/A')),
                                DataCell(Text(p['reference'] ?? 'N/A')),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
        ),
        AdminPager(
          page: _paidPage,
          hasMore: _paidHasMore,
          loading: _paidLoading,
          onPageChange: (p) {
            setState(() => _paidPage = p);
            _loadPaid();
          },
        ),
      ]),
    );
  }

  // ── Settlement history tab ──
  Widget _settlementsTab() {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _filterBar([
          AdminSearchField(
            hint: 'Search lawyer, settlement ID, reference…',
            onChanged: (v) {
              _search = v;
              _applyFilters();
            },
          ),
          for (final s in const [
            ('', 'All'),
            ('pending', 'Pending'),
            ('processing', 'Processing'),
            ('paid', 'Paid'),
            ('failed', 'Failed'),
            ('cancelled', 'Cancelled')
          ])
            AdminFilterChip(
                label: s.$2,
                selected: _settlementStatusFilter == s.$1,
                onTap: () {
                  setState(() => _settlementStatusFilter = s.$1);
                  _applyFilters();
                }),
          _HeaderIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh',
              onTap: () => _loadSettlements()),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 460,
          child: _settlementsLoading
              ? const AdminTableSkeleton(columns: 9)
              : _settlements.isEmpty
                  ? const AdminEmptyState(message: 'No settlements found')
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          dataRowMinHeight: 46,
                          dataRowMaxHeight: 52,
                          headingRowColor: WidgetStateProperty.all(kAdminBg),
                          columns: const [
                            DataColumn(label: Text('Settlement ID')),
                            DataColumn(label: Text('Lawyer')),
                            DataColumn(label: Text('Gross')),
                            DataColumn(label: Text('Commission')),
                            DataColumn(label: Text('GST')),
                            DataColumn(label: Text('Net Payout')),
                            DataColumn(label: Text('Txns')),
                            DataColumn(label: Text('Payout Date')),
                            DataColumn(label: Text('Status')),
                          ],
                          rows: _settlements.map((s) {
                            return DataRow(
                              onSelectChanged: (_) =>
                                  _showSettlementDetail(s['settlement_id']),
                              cells: [
                                DataCell(Text(
                                    '${s['settlement_id']}'.substring(0, 8),
                                    style: const TextStyle(fontSize: 11))),
                                DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _Avatar(name: s['lawyer_name'] ?? '?'),
                                      const SizedBox(width: 8),
                                      Text(s['lawyer_name'] ?? '-'),
                                    ])),
                                DataCell(Text(
                                    fmtRupees(s['gross_earnings'] as num?))),
                                DataCell(Text(fmtRupees(
                                    s['platform_commission'] as num?))),
                                DataCell(Text(fmtRupees(s['gst'] as num?))),
                                DataCell(Text(
                                    fmtRupees(s['net_payout'] as num?),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700))),
                                DataCell(
                                    Text('${s['transaction_count'] ?? 0}')),
                                DataCell(Text(s['payout_date'] == null
                                    ? 'Pending'
                                    : fmtDate(s['payout_date']))),
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
          page: _settlementsPage,
          hasMore: _settlementsHasMore,
          loading: _settlementsLoading,
          onPageChange: (p) {
            setState(() => _settlementsPage = p);
            _loadSettlements();
          },
        ),
      ]),
    );
  }

  void _showSettlementDetail(String id) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          width: 580,
          constraints: const BoxConstraints(maxHeight: 680),
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _repo
                .settlementDetail(id)
                .then((r) => (r['data'] as Map<String, dynamic>?) ?? {}),
            builder: (context, snap) {
              if (snap.hasError) {
                return _DialogError(
                    message: 'Failed to load settlement detail.',
                    onClose: () => Navigator.pop(context));
              }
              if (!snap.hasData) {
                return const SizedBox(
                    height: 220,
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.4)));
              }
              final s =
                  (snap.data!['settlement'] as Map<String, dynamic>?) ?? {};
              final txns = (snap.data!['transactions'] as List?) ?? [];
              return SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Expanded(
                            child: Text('Settlement Detail',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800))),
                        IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded)),
                      ]),
                      AdminBadge(s['status'] ?? '',
                          AdminBadge.colorFor(s['status'] ?? '')),
                      const Divider(height: 26),
                      _dr('Settlement ID', s['settlement_id']),
                      _dr('Lawyer',
                          '${s['lawyer_name']} (${s['lawyer_email']})'),
                      _dr('Lawyer ID', s['lawyer_id']),
                      _dr('Gross Earnings',
                          fmtRupees(s['gross_earnings'] as num?)),
                      _dr('Platform Commission',
                          fmtRupees(s['platform_commission'] as num?)),
                      _dr('GST', fmtRupees(s['gst'] as num?)),
                      _dr('Net Payout', fmtRupees(s['net_payout'] as num?)),
                      _dr('Number of Transactions', s['transaction_count']),
                      _dr('Settlement Date', fmtDate(s['settlement_date'])),
                      _dr(
                          'Payout Date',
                          s['payout_date'] == null
                              ? 'Pending'
                              : fmtDate(s['payout_date'])),
                      _dr('Payment Method', s['payment_method']),
                      _dr('Reference / UTR', s['reference']),
                      if ((s['notes'] ?? '').toString().isNotEmpty)
                        _dr('Notes', s['notes']),
                      const Divider(height: 26),
                      _sectionLabel('Included Transactions'),
                      const SizedBox(height: 10),
                      if (txns.isEmpty)
                        const Text('No transaction records.',
                            style: TextStyle(
                                color: kAdminTextMuted, fontSize: 12.5))
                      else
                        ...txns.map((t) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: kAdminBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: kAdminBorder)),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _dr('Client', t['client_name']),
                                    _dr('Service Type', t['service_type']),
                                    _dr('Date', t['date']),
                                    _dr('Amount',
                                        fmtRupees(t['amount'] as num?)),
                                    _dr(
                                        'Payment Reference',
                                        (t['payment_reference'] ?? '')
                                                .toString()
                                                .isEmpty
                                            ? 'N/A'
                                            : t['payment_reference']),
                                  ]),
                            )),
                    ]),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _dr(String label, dynamic value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 150,
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

  // ── Export (unchanged behavior, only invoked from the redesigned header) ──
  List<List<String>> _rowsToTable(String tab, List<dynamic> rows) {
    switch (tab) {
      case 'LawyerEarnings':
        return [
          [
            'Lawyer',
            'Email',
            'Consultations',
            'Gross Earnings',
            'Commission',
            'GST',
            'Net Payout',
            'Pending',
            'Paid',
            'Status'
          ],
          ...rows.map((l) => [
                '${l['name'] ?? ''}',
                '${l['email'] ?? ''}',
                '${l['total_consultations'] ?? 0}',
                fmtRupees(l['gross_earnings'] as num?),
                fmtRupees(l['platform_commission'] as num?),
                fmtRupees(l['gst'] as num?),
                fmtRupees(l['net_payout'] as num?),
                fmtRupees(l['pending_amount'] as num?),
                fmtRupees(l['paid_amount'] as num?),
                '${l['payout_status'] ?? ''}',
              ]),
        ];
      case 'PaidPayouts':
        return [
          [
            'Lawyer',
            'Amount',
            'Settlement ID',
            'Transactions',
            'Payout Date',
            'Method',
            'Reference'
          ],
          ...rows.map((p) => [
                '${p['lawyer_name'] ?? ''}',
                fmtRupees(p['payout_amount'] as num?),
                '${p['settlement_id'] ?? ''}',
                '${p['transaction_count'] ?? 0}',
                fmtDate(p['payout_date']),
                '${p['payment_method'] ?? 'N/A'}',
                '${p['reference'] ?? 'N/A'}',
              ]),
        ];
      default:
        return [
          [
            'Settlement ID',
            'Lawyer',
            'Gross',
            'Commission',
            'GST',
            'Net Payout',
            'Transactions',
            'Payout Date',
            'Status'
          ],
          ...rows.map((s) => [
                '${s['settlement_id'] ?? ''}',
                '${s['lawyer_name'] ?? ''}',
                fmtRupees(s['gross_earnings'] as num?),
                fmtRupees(s['platform_commission'] as num?),
                fmtRupees(s['gst'] as num?),
                fmtRupees(s['net_payout'] as num?),
                '${s['transaction_count'] ?? 0}',
                s['payout_date'] == null
                    ? 'Pending'
                    : fmtDate(s['payout_date']),
                '${s['status'] ?? ''}',
              ]),
        ];
    }
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
    final ok =
        triggerBrowserDownload(bytes, 'libra_payouts_$tab.csv', 'text/csv');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('CSV export is only available in the Chrome admin panel.')));
    }
  }

  Future<void> _exportPdf(String section, List<dynamic> rows) async {
    final table = _rowsToTable(
        section == 'Lawyer Earnings'
            ? 'LawyerEarnings'
            : (section == 'Paid Payouts' ? 'PaidPayouts' : 'Settlements'),
        rows);
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
                      pw.Text('Super Admin — Payouts & Settlements Report',
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
          pw.Text('Section: $section (${rows.length} records)',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          pw.Text('Summary',
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Bullet(
              text:
                  'Total gross lawyer earnings: ${fmtRupees(_n('total_lawyer_earnings'))}'),
          pw.Bullet(
              text:
                  'Total platform commission: ${fmtRupees(_n('total_platform_commission'))}'),
          pw.Bullet(text: 'Total GST: ${fmtRupees(_n('total_gst'))}'),
          pw.Bullet(
              text:
                  'Total net lawyer payouts: ${fmtRupees(_n('total_net_lawyer_payout'))}'),
          pw.Bullet(
              text: 'Pending payouts: ${fmtRupees(_n('pending_payout'))}'),
          pw.Bullet(text: 'Paid payouts: ${fmtRupees(_n('paid_payout'))}'),
          pw.SizedBox(height: 14),
          pw.Text('Detailed Records — $section',
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
        bytes, 'libra_payouts_$section.pdf', 'application/pdf');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('PDF export is only available in the Chrome admin panel.')));
    }
  }
}

// ── Small presentational helpers, local to this screen ──

class _KpiSpec {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final int? tabIndex;
  _KpiSpec(this.label, this.value, this.icon, this.color, this.tabIndex);
}

class _KpiCard extends StatefulWidget {
  final _KpiSpec spec;
  final VoidCallback? onTap;
  const _KpiCard({required this.spec, this.onTap});

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kAdminCard,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
            color: _hovering && widget.onTap != null
                ? s.color.withValues(alpha: 0.4)
                : kAdminBorder),
        boxShadow: [
          if (_hovering && widget.onTap != null)
            BoxShadow(
                color: s.color.withValues(alpha: 0.16),
                blurRadius: 16,
                offset: const Offset(0, 6))
          else
            BoxShadow(
                color: kAdminTextPri.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3)),
        ],
      ),
      transform: _hovering && widget.onTap != null
          ? (Matrix4.identity()..translateByDouble(0.0, -2.0, 0.0, 1.0))
          : Matrix4.identity(),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: s.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11)),
          child: Icon(s.icon, color: s.color, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: kAdminTextPri,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: kAdminTextMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
        ),
        if (widget.onTap != null)
          Icon(Icons.arrow_outward_rounded,
              size: 13, color: kAdminTextMuted.withValues(alpha: 0.5)),
      ]),
    );
    if (widget.onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(onTap: widget.onTap, child: card),
    );
  }
}

class _HeaderIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _HeaderIconButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _hovering
                    ? kAdminAccent.withValues(alpha: 0.08)
                    : kAdminCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _hovering
                        ? kAdminAccent.withValues(alpha: 0.35)
                        : kAdminBorder),
              ),
              child: Icon(widget.icon,
                  size: 17, color: _hovering ? kAdminAccent : kAdminTextMuted),
            ),
          ),
        ),
      );
}

class _ExportButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ExportButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  State<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<_ExportButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color:
                  _hovering ? kAdminAccent.withValues(alpha: 0.08) : kAdminCard,
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: _hovering ? kAdminAccent : kAdminBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.icon,
                  size: 16, color: _hovering ? kAdminAccent : kAdminTextPri),
              const SizedBox(width: 6),
              Text(widget.label,
                  style: TextStyle(
                      color: _hovering ? kAdminAccent : kAdminTextPri,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  const _Avatar({required this.name, this.size = 28});

  static const _palette = [
    kAdminAccent,
    Color(0xFF7C3AED),
    kAdminGreen,
    kAdminAmber,
    Color(0xFFDB2777)
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initials = trimmed.isEmpty
        ? '?'
        : trimmed
            .split(RegExp(r'\s+'))
            .take(2)
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
            .join();
    final color =
        _palette[trimmed.isEmpty ? 0 : trimmed.codeUnitAt(0) % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Text(initials,
          style: TextStyle(
              color: color,
              fontSize: size * 0.38,
              fontWeight: FontWeight.w800)),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kAdminRed.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kAdminRed.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: kAdminRed, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style:
                      const TextStyle(color: kAdminTextPri, fontSize: 12.5))),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
}

class _DialogError extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  const _DialogError({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 220,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline_rounded, color: kAdminRed, size: 30),
          const SizedBox(height: 10),
          Text(message,
              style: const TextStyle(color: kAdminTextMuted, fontSize: 12.5)),
          const SizedBox(height: 12),
          TextButton(onPressed: onClose, child: const Text('Close')),
        ]),
      );
}

class _ChartSeries {
  final String label;
  final Color color;
  final List<dynamic> points;
  _ChartSeries(this.label, this.color, this.points);
}

/// A lightweight multi-series line/area chart drawn with CustomPaint —
/// deliberately no new charting dependency, consistent with the rest of the
/// admin panel's hand-rolled bar charts (see admin_subscriptions_screen.dart
/// and admin_analytics_screen.dart). Purely a rendering of whatever real
/// values the trends API returns; nothing is computed or invented here.
class _MultiLineChart extends StatelessWidget {
  final List<_ChartSeries> series;
  final double progress;
  const _MultiLineChart({required this.series, this.progress = 1});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _LineChartPainter(series: series, progress: progress),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_ChartSeries> series;
  final double progress;
  _LineChartPainter({required this.series, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || series.first.points.isEmpty) return;
    final n = series.first.points.length;
    if (n < 2) return;

    double maxV = 0;
    for (final s in series) {
      for (final p in s.points) {
        final v = ((p['value'] as num?) ?? 0).toDouble();
        if (v > maxV) maxV = v;
      }
    }
    if (maxV <= 0) maxV = 1;

    const leftPad = 4.0;
    const bottomPad = 4.0;
    final chartW = size.width - leftPad;
    final chartH = size.height - bottomPad;

    // Gridlines
    final gridPaint = Paint()
      ..color = kAdminBorder.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chartH * i / 3;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
    }

    for (final s in series) {
      final path = Path();
      final fillPath = Path();
      for (var i = 0; i < s.points.length; i++) {
        final v = ((s.points[i]['value'] as num?) ?? 0).toDouble();
        final x = leftPad + chartW * (i / (n - 1));
        final y = chartH - (v / maxV) * chartH * progress;
        if (i == 0) {
          path.moveTo(x, y);
          fillPath.moveTo(x, chartH);
          fillPath.lineTo(x, y);
        } else {
          path.lineTo(x, y);
          fillPath.lineTo(x, y);
        }
      }
      fillPath.lineTo(leftPad + chartW, chartH);
      fillPath.close();

      if (s == series.first) {
        final fillPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              s.color.withValues(alpha: 0.16),
              s.color.withValues(alpha: 0.0)
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
        canvas.drawPath(fillPath, fillPaint);
      }

      final linePaint = Paint()
        ..color = s.color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.series != series;
}
