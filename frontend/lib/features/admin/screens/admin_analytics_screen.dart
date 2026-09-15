import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/auto_refresh_service.dart';
import '../../lawyer/utils/browser_download.dart';
import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

/// Super Admin → Analytics & Reports.
///
/// Every figure here is read straight from the existing admin analytics/
/// revenue/subscriptions endpoints (see admin_analytics_controller.go's top
/// comment) — this screen adds no new accounting, only a dashboard over
/// numbers that already exist. GST/platform fee/lawyer payout render "N/A"
/// on rows where that source (a consultation, a subscription payment) has
/// no such concept — never a guessed figure.
class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});
  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

enum _QuickRange { today, yesterday, last7, last30, thisMonth, lastMonth, thisYear, custom }

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> with SingleTickerProviderStateMixin {
  final _repo = AdminRepository();
  late TabController _tabCtrl;

  _QuickRange _range = _QuickRange.last30;
  DateTimeRange? _customRange;

  bool _usersLoading = true;
  Map<String, dynamic> _users = {};
  bool _bookingsLoading = true;
  Map<String, dynamic> _bookings = {};
  bool _revenueLoading = true;
  Map<String, dynamic> _revenue = {};
  bool _subStatsLoading = true;
  Map<String, dynamic> _subStats = {};
  bool _trendsLoading = true;
  Map<String, dynamic> _trends = {};

  bool _txnLoading = true;
  List<dynamic> _transactions = [];
  int _txnPage = 1;
  bool _txnHasMore = false;
  String _search = '';
  String _serviceFilter = '';
  String _statusFilter = '';
  String _lawyerFilter = '';
  String _clientFilter = '';

  static const _tabs = ['Overview', 'Growth', 'Bookings', 'Revenue', 'Report'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _loadAll();
    AutoRefreshService.instance.register('admin_analytics', () => _loadAll(silent: true));
  }

  @override
  void dispose() {
    AutoRefreshService.instance.unregister('admin_analytics');
    _tabCtrl.dispose();
    super.dispose();
  }

  DateTimeRange? get _resolvedRange {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case _QuickRange.today:
        return DateTimeRange(start: today, end: today);
      case _QuickRange.yesterday:
        final y = today.subtract(const Duration(days: 1));
        return DateTimeRange(start: y, end: y);
      case _QuickRange.last7:
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case _QuickRange.last30:
        return DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
      case _QuickRange.thisMonth:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: today);
      case _QuickRange.lastMonth:
        final firstOfThisMonth = DateTime(now.year, now.month, 1);
        final lastMonthEnd = firstOfThisMonth.subtract(const Duration(days: 1));
        return DateTimeRange(start: DateTime(lastMonthEnd.year, lastMonthEnd.month, 1), end: lastMonthEnd);
      case _QuickRange.thisYear:
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: today);
      case _QuickRange.custom:
        return _customRange;
    }
  }

  String? get _fromStr {
    final r = _resolvedRange;
    return r == null ? null : DateFormat('yyyy-MM-dd').format(r.start);
  }

  String? get _toStr {
    final r = _resolvedRange;
    return r == null ? null : DateFormat('yyyy-MM-dd').format(r.end);
  }

  int get _trendDays {
    final r = _resolvedRange;
    if (r == null) return 30;
    final d = r.end.difference(r.start).inDays + 1;
    return d.clamp(1, 180);
  }

  Future<void> _loadAll({bool silent = false}) async {
    await Future.wait([
      _loadUsers(silent: silent),
      _loadBookings(silent: silent),
      _loadRevenue(silent: silent),
      _loadSubStats(silent: silent),
      _loadTrends(silent: silent),
      _loadTransactions(silent: silent),
    ]);
  }

  Future<void> _loadUsers({bool silent = false}) async {
    if (!silent) setState(() => _usersLoading = true);
    try {
      final res = await _repo.analyticsUsers(from: _fromStr, to: _toStr);
      if (!mounted) return;
      setState(() {
        _users = (res['data'] as Map<String, dynamic>?) ?? {};
        _usersLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _usersLoading = false);
    }
  }

  Future<void> _loadBookings({bool silent = false}) async {
    if (!silent) setState(() => _bookingsLoading = true);
    try {
      final res = await _repo.analyticsBookings(from: _fromStr, to: _toStr);
      if (!mounted) return;
      setState(() {
        _bookings = (res['data'] as Map<String, dynamic>?) ?? {};
        _bookingsLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _bookingsLoading = false);
    }
  }

  Future<void> _loadRevenue({bool silent = false}) async {
    if (!silent) setState(() => _revenueLoading = true);
    try {
      final res = await _repo.revenue(from: _fromStr, to: _toStr);
      if (!mounted) return;
      setState(() {
        _revenue = (res['data'] as Map<String, dynamic>?) ?? {};
        _revenueLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _revenueLoading = false);
    }
  }

  Future<void> _loadSubStats({bool silent = false}) async {
    if (!silent) setState(() => _subStatsLoading = true);
    try {
      final res = await _repo.subscriptionStats();
      if (!mounted) return;
      setState(() {
        _subStats = (res['data'] as Map<String, dynamic>?) ?? {};
        _subStatsLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _subStatsLoading = false);
    }
  }

  Future<void> _loadTrends({bool silent = false}) async {
    if (!silent) setState(() => _trendsLoading = true);
    try {
      final res = await _repo.analyticsTrends(days: _trendDays, to: _toStr);
      if (!mounted) return;
      setState(() {
        _trends = (res['data'] as Map<String, dynamic>?) ?? {};
        _trendsLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _trendsLoading = false);
    }
  }

  Future<void> _loadTransactions({bool silent = false}) async {
    if (!silent) setState(() => _txnLoading = true);
    try {
      final res = await _repo.analyticsTransactions(
        search: _search,
        service: _serviceFilter,
        status: _statusFilter,
        lawyer: _lawyerFilter,
        client: _clientFilter,
        from: _fromStr,
        to: _toStr,
        page: _txnPage,
      );
      if (!mounted) return;
      setState(() {
        _transactions = (res['data'] as List?) ?? [];
        _txnHasMore = (res['meta']?['has_more'] as bool?) ?? false;
        _txnLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _txnLoading = false);
    }
  }

  void _setRange(_QuickRange r) {
    setState(() => _range = r);
    _loadAll();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
        context: context, firstDate: DateTime(now.year - 3), lastDate: DateTime(now.year + 1), initialDateRange: _customRange);
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _range = _QuickRange.custom;
      });
      _loadAll();
    }
  }

  void _applyTxnFilters() {
    _txnPage = 1;
    _loadTransactions();
  }

  num _u(String k) => (_users[k] as num?) ?? 0;
  num _b(String k) => (_bookings[k] as num?) ?? 0;
  num _r(String k) => ((_revenue['summary'] as Map<String, dynamic>?)?[k] as num?) ?? 0;
  num _s(String k) => (_subStats[k] as num?) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/analytics',
      title: 'Analytics & Reports',
      actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => _loadAll())],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _rangeSelector(),
        const SizedBox(height: 16),
        _summaryCards(),
        const SizedBox(height: 20),
        AdminSectionCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            labelColor: kAdminAccent,
            unselectedLabelColor: kAdminTextMuted,
            indicatorColor: kAdminAccent,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 760,
          child: TabBarView(controller: _tabCtrl, children: [
            _overviewTab(),
            _growthTab(),
            _bookingsTab(),
            _revenueTab(),
            _reportTab(),
          ]),
        ),
      ]),
    );
  }

  Widget _rangeSelector() {
    const labels = {
      _QuickRange.today: 'Today',
      _QuickRange.yesterday: 'Yesterday',
      _QuickRange.last7: 'Last 7 Days',
      _QuickRange.last30: 'Last 30 Days',
      _QuickRange.thisMonth: 'This Month',
      _QuickRange.lastMonth: 'Last Month',
      _QuickRange.thisYear: 'This Year',
    };
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final e in labels.entries) AdminFilterChip(label: e.value, selected: _range == e.key, onTap: () => _setRange(e.key)),
      GestureDetector(
        onTap: _pickCustomRange,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _range == _QuickRange.custom ? kAdminAccent : kAdminBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _range == _QuickRange.custom ? kAdminAccent : kAdminBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.date_range_rounded, size: 14, color: _range == _QuickRange.custom ? Colors.white : kAdminTextPri),
            const SizedBox(width: 6),
            Text(
                _range == _QuickRange.custom && _customRange != null
                    ? '${DateFormat('d MMM').format(_customRange!.start)} - ${DateFormat('d MMM').format(_customRange!.end)}'
                    : 'Custom Range',
                style: TextStyle(
                    color: _range == _QuickRange.custom ? Colors.white : kAdminTextPri,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]);
  }

  Widget _summaryCards() {
    if (_usersLoading || _bookingsLoading || _revenueLoading || _subStatsLoading) {
      return const AdminStatGridSkeleton(count: 12);
    }
    final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    // Route is null for a derived/aggregate figure that has no single list
    // of its own (e.g. "Net Platform Revenue" isn't a table) — those cards
    // render without the tap affordance, same convention as the main
    // Dashboard's stat cards.
    final cards = [
      ('Total Users', '${_u('total_users')}', Icons.people_alt_rounded, kAdminAccent, '/admin/users'),
      ('Total Lawyers', '${_u('lawyer_registrations')}', Icons.gavel_rounded, kAdminGold, '/admin/lawyers'),
      ('Total Clients', '${_u('client_registrations')}', Icons.person_rounded, const Color(0xFF7C3AED), '/admin/clients'),
      ('Total Students', '${_u('student_registrations')}', Icons.school_rounded, kAdminGreen, '/admin/students'),
      ('Total Bookings', '${_b('total_bookings')}', Icons.event_note_rounded, kAdminAccent, '/admin/consultations'),
      ('Total Revenue', f.format(_r('gross_revenue')), Icons.account_balance_wallet_rounded, kAdminGreen, '/admin/revenue'),
      ('GST Collected', f.format(_r('gst_collected')), Icons.receipt_rounded, kAdminAmber, '/admin/revenue'),
      ('Platform Fees', f.format(_r('platform_revenue')), Icons.business_center_rounded, kAdminAccent, '/admin/revenue'),
      ('Lawyer Payouts', f.format(_r('lawyer_earnings_gross')), Icons.savings_rounded, kAdminGold, '/admin/lawyer-earnings'),
      ('Refunds', f.format(_r('refund_amount')), Icons.replay_rounded, kAdminRed, '/admin/revenue'),
      ('Subscription Revenue', f.format(_s('total_revenue')), Icons.workspace_premium_rounded, const Color(0xFF7C3AED), '/admin/subscriptions'),
      ('Net Platform Revenue', f.format(_r('net_revenue')), Icons.account_balance_rounded, kAdminGreen, null),
    ];
    return AdminStatGrid(
      cards: cards.asMap().entries.map((e) {
        final i = e.key;
        final c = e.value;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 180 + i * 25),
          curve: Curves.easeOut,
          builder: (_, v, child) =>
              Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child)),
          child: AdminStatCard(
            label: c.$1,
            value: c.$2,
            icon: c.$3,
            color: c.$4,
            onTap: c.$5 == null ? null : () => context.go(c.$5!),
          ),
        );
      }).toList(),
    );
  }

  // ── Overview tab ──
  Widget _overviewTab() {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _chartCard('User Growth', _trends['user_growth'], kAdminAccent),
        const SizedBox(height: 16),
        _chartCard('Bookings', _trends['bookings'], kAdminGold),
        const SizedBox(height: 16),
        _chartCard('Revenue (₹)', _trends['revenue'], kAdminGreen),
      ]),
    );
  }

  // ── Growth tab ──
  Widget _growthTab() {
    if (_usersLoading) return const AdminLoader(topPadding: 40);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AdminSectionCard(
          title: 'User Analytics',
          child: Wrap(spacing: 16, runSpacing: 16, children: [
            _tile('New Today', '${_u('new_today')}', kAdminAccent),
            _tile('New This Week', '${_u('new_this_week')}', kAdminAccent),
            _tile('New This Month', '${_u('new_this_month')}', kAdminAccent),
            _tile('New In Range', '${_u('new_in_range')}', kAdminGold),
            _tile('Active Users', '${_u('active_users')}', kAdminGreen),
            _tile('Suspended Users', '${_u('suspended_users')}', kAdminRed),
            _tile('Growth %', '${(_u('user_growth_percent')).toStringAsFixed(1)}%',
                _u('user_growth_percent') >= 0 ? kAdminGreen : kAdminRed),
          ]),
        ),
        const SizedBox(height: 16),
        _chartCard('User Growth', _trends['user_growth'], kAdminAccent),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _chartCard('Lawyer Registrations', _trends['lawyer_registrations'], kAdminGold)),
          const SizedBox(width: 16),
          Expanded(child: _chartCard('Client Registrations', _trends['client_registrations'], const Color(0xFF7C3AED))),
        ]),
      ]),
    );
  }

  // ── Bookings tab ──
  Widget _bookingsTab() {
    if (_bookingsLoading) return const AdminLoader(topPadding: 40);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AdminSectionCard(
          title: 'Booking / Consultation Analytics',
          child: Wrap(spacing: 16, runSpacing: 16, children: [
            _tile("Today's Bookings", '${_b('today_bookings')}', kAdminAccent),
            _tile('Weekly Bookings', '${_b('weekly_bookings')}', kAdminAccent),
            _tile('Monthly Bookings', '${_b('monthly_bookings')}', kAdminAccent),
            _tile('Completed', '${_b('completed_bookings')}', kAdminGreen),
            _tile('Pending', '${_b('pending_bookings')}', kAdminAmber),
            _tile('Rejected/Cancelled', '${_b('rejected_cancelled_bookings')}', kAdminRed),
            _tile('Avg Session Duration', '${(_b('average_duration_minutes')).toStringAsFixed(1)} min', kAdminGold),
          ]),
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          title: 'Bookings by Service Type',
          child: Row(children: [
            Expanded(child: _serviceTile('Chat', _b('chat_bookings'), kAdminAccent, Icons.chat_bubble_rounded)),
            Expanded(child: _serviceTile('Audio', _b('audio_bookings'), kAdminGold, Icons.call_rounded)),
            Expanded(child: _serviceTile('Video', _b('video_bookings'), kAdminGreen, Icons.videocam_rounded)),
            Expanded(child: _serviceTile('Visit', _b('visit_bookings'), const Color(0xFF7C3AED), Icons.meeting_room_rounded)),
          ]),
        ),
        const SizedBox(height: 16),
        _chartCard('Booking Growth', _trends['bookings'], kAdminGold),
      ]),
    );
  }

  Widget _serviceTile(String label, num value, Color color, IconData icon) => Column(children: [
        Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20)),
        const SizedBox(height: 8),
        Text('${value.toInt()}', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: kAdminTextMuted, fontSize: 11.5)),
      ]);

  // ── Revenue tab ──
  Widget _revenueTab() {
    if (_revenueLoading) return const AdminLoader(topPadding: 40);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AdminSectionCard(
          title: 'Revenue Breakdown',
          child: Wrap(spacing: 16, runSpacing: 16, children: [
            _tile('Gross Revenue', fmtRupees(_r('gross_revenue')), kAdminGreen),
            _tile('Net Revenue', fmtRupees(_r('net_revenue')), kAdminAccent),
            _tile('Lawyer Earnings (payouts)', fmtRupees(_r('lawyer_earnings_gross')), kAdminGold),
            _tile('Platform Revenue', fmtRupees(_r('platform_revenue')), kAdminAccent),
            _tile('Firm Invoice Revenue', fmtRupees(_r('firm_invoice_revenue')), kAdminGreen),
            _tile('GST Collected', fmtRupees(_r('gst_collected')), kAdminAmber),
            _tile('Refunds', fmtRupees(_r('refund_amount')), kAdminRed),
          ]),
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          title: 'Subscription Revenue',
          child: Wrap(spacing: 16, runSpacing: 16, children: [
            _tile('Total Subscriptions', '${_s('total_subscriptions')}', kAdminAccent),
            _tile('Active', '${_s('active_subscriptions')}', kAdminGreen),
            _tile('Expired', '${_s('expired_subscriptions')}', kAdminTextMuted),
            _tile('Cancelled', '${_s('cancelled_subscriptions')}', kAdminRed),
            _tile('Subscription Revenue', fmtRupees(_s('total_revenue')), const Color(0xFF7C3AED)),
          ]),
        ),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _chartCard('Revenue', _trends['revenue'], kAdminGreen)),
          const SizedBox(width: 16),
          Expanded(child: _chartCard('GST Collected', _trends['gst_collected'], kAdminAmber)),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _chartCard('Platform Fees', _trends['platform_fees'], kAdminAccent)),
          const SizedBox(width: 16),
          Expanded(child: _chartCard('Lawyer Payouts', _trends['lawyer_payouts'], kAdminGold)),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _chartCard('Refunds', _trends['refunds'], kAdminRed)),
          const SizedBox(width: 16),
          Expanded(child: _chartCard('Subscription Revenue', _trends['subscription_revenue'], const Color(0xFF7C3AED))),
        ]),
      ]),
    );
  }

  Widget _tile(String label, String value, Color color) => SizedBox(
        width: 190,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: kAdminTextMuted, fontSize: 11.5)),
        ]),
      );

  Widget _chartCard(String title, dynamic seriesData, Color color) {
    final series = (seriesData as List?) ?? [];
    if (_trendsLoading) return AdminSectionCard(title: title, child: const AdminLoader(topPadding: 20));
    final maxV =
        series.isEmpty ? 1.0 : series.map((d) => ((d['value'] as num?) ?? 0).toDouble()).reduce((a, b) => a > b ? a : b).clamp(1, double.infinity);
    return AdminSectionCard(
      title: title,
      child: SizedBox(
        height: 130,
        child: series.isEmpty
            ? const AdminEmptyState()
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: series.map((d) {
                  final v = ((d['value'] as num?) ?? 0).toDouble();
                  final h = (v / maxV) * 100 + 2;
                  return Expanded(
                    child: Tooltip(
                      message: '${d['date']}: ${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(1)}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: h,
                          decoration: BoxDecoration(color: v > 0 ? color : kAdminBorder, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
      ),
    );
  }

  // ── Report tab ──
  Widget _reportTab() {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AdminSearchField(
              hint: 'Search client, lawyer, transaction…',
              onChanged: (v) {
                _search = v;
                _applyTxnFilters();
              }),
          for (final s in const [('', 'All Services'), ('chat', 'Chat'), ('audio', 'Audio'), ('video', 'Video'), ('visit', 'Visit'), ('invoice', 'Invoice'), ('subscription', 'Subscription')])
            AdminFilterChip(
                label: s.$2,
                selected: _serviceFilter == s.$1,
                onTap: () {
                  setState(() => _serviceFilter = s.$1);
                  _applyTxnFilters();
                }),
          OutlinedButton.icon(
              onPressed: () => _exportCsv(_transactions), icon: const Icon(Icons.download_rounded, size: 16), label: const Text('CSV')),
          OutlinedButton.icon(
              onPressed: () => _exportPdf(_transactions),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
              label: const Text('PDF')),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 540,
          child: _txnLoading
              ? const AdminTableSkeleton(columns: 10)
              : _transactions.isEmpty
                  ? const AdminEmptyState()
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(kAdminBg),
                          columns: const [
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Transaction ID')),
                            DataColumn(label: Text('Client')),
                            DataColumn(label: Text('Lawyer')),
                            DataColumn(label: Text('Service')),
                            DataColumn(label: Text('Gross')),
                            DataColumn(label: Text('GST')),
                            DataColumn(label: Text('Platform Fee')),
                            DataColumn(label: Text('Payout')),
                            DataColumn(label: Text('Refund')),
                            DataColumn(label: Text('Net Revenue')),
                            DataColumn(label: Text('Status')),
                          ],
                          rows: _transactions.map((t) {
                            return DataRow(cells: [
                              DataCell(Text(fmtDate(t['date']))),
                              DataCell(Text((t['transaction_id'] ?? '').toString().isEmpty ? '-' : t['transaction_id'],
                                  style: const TextStyle(fontSize: 11))),
                              DataCell(Text((t['client_name'] ?? '').toString().isEmpty ? '-' : t['client_name'])),
                              DataCell(Text((t['lawyer_name'] ?? '').toString().isEmpty ? '-' : t['lawyer_name'])),
                              DataCell(AdminBadge(t['service_type'] ?? '', kAdminAccent)),
                              DataCell(Text(fmtRupees(t['gross_amount'] as num?), style: const TextStyle(fontWeight: FontWeight.w700))),
                              DataCell(Text(_naOrRupees(t['gst_amount']))),
                              DataCell(Text(_naOrRupees(t['platform_fee']))),
                              DataCell(Text(_naOrRupees(t['lawyer_payout']))),
                              DataCell(Text(fmtRupees(t['refund_amount'] as num?),
                                  style: TextStyle(color: (t['refund_amount'] as num? ?? 0) > 0 ? kAdminRed : kAdminTextMuted))),
                              DataCell(Text(fmtRupees(t['net_revenue'] as num?), style: const TextStyle(color: kAdminGreen, fontWeight: FontWeight.w700))),
                              DataCell(AdminBadge(t['status'] ?? '', AdminBadge.colorFor(t['status'] ?? ''))),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ),
        ),
        AdminPager(
          page: _txnPage,
          hasMore: _txnHasMore,
          loading: _txnLoading,
          onPageChange: (p) {
            setState(() => _txnPage = p);
            _loadTransactions();
          },
        ),
      ]),
    );
  }

  String _naOrRupees(dynamic v) => v == null ? 'N/A' : fmtRupees(v as num?);

  // ── Export ──
  List<List<String>> _toTable(List<dynamic> rows) => [
        ['Date', 'Transaction ID', 'Client', 'Lawyer', 'Service', 'Gross', 'GST', 'Platform Fee', 'Payout', 'Refund', 'Net Revenue', 'Status'],
        ...rows.map((t) => [
              fmtDate(t['date']),
              '${t['transaction_id'] ?? ''}',
              '${t['client_name'] ?? ''}',
              '${t['lawyer_name'] ?? ''}',
              '${t['service_type'] ?? ''}',
              fmtRupees(t['gross_amount'] as num?),
              _naOrRupees(t['gst_amount']),
              _naOrRupees(t['platform_fee']),
              _naOrRupees(t['lawyer_payout']),
              fmtRupees(t['refund_amount'] as num?),
              fmtRupees(t['net_revenue'] as num?),
              '${t['status'] ?? ''}',
            ]),
      ];

  void _exportCsv(List<dynamic> rows) {
    final table = _toTable(rows);
    final csv = table
        .map((row) => row
            .map((cell) {
              final escaped = cell.replaceAll('"', '""');
              return escaped.contains(',') || escaped.contains('"') || escaped.contains('\n') ? '"$escaped"' : escaped;
            })
            .join(','))
        .join('\r\n');
    final bytes = Uint8List.fromList(csv.codeUnits);
    final ok = triggerBrowserDownload(bytes, 'libra_analytics_report.csv', 'text/csv');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('CSV export is only available in the Chrome admin panel.')));
    }
  }

  Future<void> _exportPdf(List<dynamic> rows) async {
    final table = _toTable(rows);
    final doc = pw.Document();
    final now = DateFormat('d MMM yyyy, h:mm a').format(DateTime.now());
    final r = _resolvedRange;
    final rangeLabel = r == null ? 'All time' : '${DateFormat('d MMM yyyy').format(r.start)} – ${DateFormat('d MMM yyyy').format(r.end)}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('LIBRA LAW', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.Text('Super Admin — Analytics & Reports', style: const pw.TextStyle(fontSize: 12)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('Generated: $now', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Range: $rangeLabel', style: const pw.TextStyle(fontSize: 9)),
            ]),
          ]),
          pw.SizedBox(height: 10),
          pw.Text('Summary', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Bullet(text: 'Total Users: ${_u('total_users')}   Lawyers: ${_u('lawyer_registrations')}   Clients: ${_u('client_registrations')}   Students: ${_u('student_registrations')}'),
          pw.Bullet(text: 'Total Bookings: ${_b('total_bookings')}   Completed: ${_b('completed_bookings')}   Pending: ${_b('pending_bookings')}'),
          pw.Bullet(text: 'Gross Revenue: ${fmtRupees(_r('gross_revenue'))}   Net Revenue: ${fmtRupees(_r('net_revenue'))}'),
          pw.Bullet(text: 'GST Collected: ${fmtRupees(_r('gst_collected'))}   Platform Fees: ${fmtRupees(_r('platform_revenue'))}'),
          pw.Bullet(text: 'Lawyer Payouts: ${fmtRupees(_r('lawyer_earnings_gross'))}   Refunds: ${fmtRupees(_r('refund_amount'))}'),
          pw.Bullet(text: 'Subscription Revenue: ${fmtRupees(_s('total_revenue'))}'),
          pw.SizedBox(height: 14),
          pw.Text('Detailed Transactions (${rows.length} records)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: table.first,
            data: table.skip(1).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final ok = triggerBrowserDownload(bytes, 'libra_analytics_report.pdf', 'application/pdf');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('PDF export is only available in the Chrome admin panel.')));
    }
  }
}
