import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

/// The Admin Panel's landing page. Every figure here comes from
/// GET /admin/stats, which aggregates live against consultations,
/// payment_orders, invoices, cases, documents and hearings — see that
/// handler's doc comment in admin_controller.go for exactly how each number
/// (especially the revenue split) is computed.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = {};
  List<dynamic> _registrations = [];
  List<dynamic> _consultationsTrend = [];
  List<dynamic> _revenueTrend = [];
  Map<String, dynamic> _roleDist = {};

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
      final res = await _repo.stats();
      final data = res['data'] as Map<String, dynamic>? ?? {};
      setState(() {
        _summary = (data['summary'] as Map<String, dynamic>?) ?? {};
        _registrations = (data['registrations_14d'] as List?) ?? [];
        _consultationsTrend = (data['consultations_14d'] as List?) ?? [];
        _revenueTrend = (data['revenue_14d'] as List?) ?? [];
        _roleDist = (data['role_distribution'] as Map<String, dynamic>?) ?? {};
        _loading = false;
      });
    } on AdminException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  num _n(String key) => (_summary[key] as num?) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin',
      title: 'Dashboard',
      actions: [
        IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load, tooltip: 'Refresh'),
      ],
      child: _loading
          ? const Padding(
              padding: EdgeInsets.only(top: 100), child: Center(child: CircularProgressIndicator()))
          : _error != null
              ? AdminEmptyState(message: _error!)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _statsGrid(),
                  const SizedBox(height: 20),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 2, child: _trendsCard()),
                    const SizedBox(width: 16),
                    Expanded(child: _roleDistCard()),
                  ]),
                  const SizedBox(height: 20),
                  _revenueBreakdown(),
                  const SizedBox(height: 20),
                  if (_n('pending_verification') > 0) _pendingVerificationBanner(),
                ]),
    );
  }

  Widget _statsGrid() {
    final cards = [
      ('Total Users', '${_n('total_users')}', Icons.people_alt_rounded, kAdminAccent, null),
      ('Total Lawyers', '${_n('total_lawyers')}', Icons.gavel_rounded, kAdminGold, '${_n('active_lawyers')} active'),
      ('Total Students', '${_n('total_students')}', Icons.school_rounded, kAdminGreen, '${_n('active_students')} active'),
      ('Total Clients', '${_n('total_clients')}', Icons.person_rounded, const Color(0xFF7C3AED), '${_n('active_clients')} active'),
      ('Pending Verification', '${_n('pending_verification')}', Icons.pending_actions_rounded, kAdminAmber, null),
      ('Total Consultations', '${_n('total_consultations')}', Icons.event_note_rounded, kAdminAccent, null),
      ('Pending Consultations', '${_n('pending_consultations')}', Icons.hourglass_top_rounded, kAdminAmber, null),
      ('Completed Consultations', '${_n('completed_consultations')}', Icons.check_circle_rounded, kAdminGreen, null),
      ('Cancelled Consultations', '${_n('cancelled_consultations')}', Icons.cancel_rounded, kAdminRed, null),
      ('Total Payments', '${_n('total_payments')}', Icons.payments_rounded, kAdminAccent, null),
      ('Successful Payments', '${_n('successful_payments')}', Icons.check_circle_rounded, kAdminGreen, null),
      ('Failed Payments', '${_n('failed_payments')}', Icons.error_rounded, kAdminRed, null),
      ('Pending Payments', '${_n('pending_payments')}', Icons.schedule_rounded, kAdminAmber, null),
      ('Total Revenue', fmtRupees(_n('total_revenue')), Icons.account_balance_wallet_rounded, kAdminGreen, 'This month: ${fmtRupees(_n('monthly_revenue'))}'),
      ('Lawyer Earnings', fmtRupees(_n('lawyer_earnings')), Icons.savings_rounded, kAdminGold, null),
      ('Platform Revenue', fmtRupees(_n('platform_revenue')), Icons.business_center_rounded, kAdminAccent, 'Subscriptions'),
      ('Refund Amount', fmtRupees(_n('refund_amount')), Icons.replay_rounded, kAdminRed, null),
      ('Total Cases', '${_n('total_cases')}', Icons.cases_rounded, const Color(0xFF7C3AED), null),
      ('Total Documents', '${_n('total_documents')}', Icons.folder_shared_rounded, kAdminAccent, null),
      ('Total Hearings', '${_n('total_hearings')}', Icons.account_balance_rounded, kAdminAmber, null),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 1200 ? 5 : (constraints.maxWidth > 800 ? 3 : 2);
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: cards
            .map((c) => AdminStatCard(label: c.$1, value: c.$2, icon: c.$3, color: c.$4, subtitle: c.$5))
            .toList(),
      );
    });
  }

  Widget _trendsCard() => AdminSectionCard(
        title: 'Trends (last 14 days)',
        child: Column(children: [
          _MiniBarChart(label: 'New Registrations', data: _registrations, color: kAdminAccent),
          const SizedBox(height: 18),
          _MiniBarChart(label: 'Consultations Booked', data: _consultationsTrend, color: kAdminGold),
          const SizedBox(height: 18),
          _MiniBarChart(label: 'Consultation Revenue (₹)', data: _revenueTrend, color: kAdminGreen),
        ]),
      );

  Widget _roleDistCard() {
    final lawyers = (_roleDist['lawyers'] as num?) ?? 0;
    final students = (_roleDist['students'] as num?) ?? 0;
    final clients = (_roleDist['clients'] as num?) ?? 0;
    final total = (lawyers + students + clients).clamp(1, double.infinity);
    return AdminSectionCard(
      title: 'User Distribution',
      child: Column(children: [
        _distRow('Lawyers', lawyers, total, kAdminGold),
        const SizedBox(height: 12),
        _distRow('Students', students, total, kAdminGreen),
        const SizedBox(height: 12),
        _distRow('Clients', clients, total, const Color(0xFF7C3AED)),
      ]),
    );
  }

  Widget _distRow(String label, num value, num total, Color color) {
    final frac = value / total;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(color: kAdminTextPri, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('${value.toInt()}', style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
            value: frac.toDouble(), minHeight: 8, backgroundColor: kAdminBg, color: color),
      ),
    ]);
  }

  Widget _revenueBreakdown() => AdminSectionCard(
        title: 'Revenue Breakdown',
        child: Row(children: [
          Expanded(child: _revenueTile('Lawyer Earnings (consultations)', _n('lawyer_earnings'), kAdminGold)),
          Expanded(child: _revenueTile('Platform Revenue (subs + invoice fees)', _n('platform_revenue'), kAdminAccent)),
          Expanded(child: _revenueTile('Firm Invoice Revenue (base only)', _n('firm_invoice_total'), kAdminGreen)),
          Expanded(child: _revenueTile('GST Collected (pass-through)', _n('gst_collected'), kAdminAmber)),
          Expanded(child: _revenueTile('Refunds', _n('refund_amount'), kAdminRed)),
        ]),
      );

  Widget _revenueTile(String label, num value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(fmtRupees(value), style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: kAdminTextMuted, fontSize: 11.5)),
      ]);

  Widget _pendingVerificationBanner() => GestureDetector(
        onTap: () => context.go('/admin/verify-lawyers'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: kAdminAmber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kAdminAmber.withValues(alpha: 0.3))),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: kAdminAmber),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${_n('pending_verification').toInt()} lawyer(s) awaiting document verification',
                  style: const TextStyle(color: kAdminTextPri, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: kAdminAmber),
          ]),
        ),
      );
}

/// A minimal bar chart drawn with plain Containers — no charting package
/// dependency added just for the dashboard's trend lines.
class _MiniBarChart extends StatelessWidget {
  final String label;
  final List<dynamic> data;
  final Color color;
  const _MiniBarChart({required this.label, required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final values = data.map((d) => ((d['value'] as num?) ?? 0).toDouble()).toList();
    final maxV = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b).clamp(1, double.infinity);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: kAdminTextMuted, fontSize: 11.5, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      SizedBox(
        height: 56,
        child: data.isEmpty
            ? const SizedBox()
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.map((d) {
                  final v = ((d['value'] as num?) ?? 0).toDouble();
                  final h = maxV == 0 ? 2.0 : (v / maxV) * 50 + 2;
                  return Expanded(
                    child: Tooltip(
                      message: '${d['date']}: ${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Container(
                          height: h,
                          decoration: BoxDecoration(
                              color: v > 0 ? color : kAdminBorder,
                              borderRadius: BorderRadius.circular(3)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
      ),
    ]);
  }
}
