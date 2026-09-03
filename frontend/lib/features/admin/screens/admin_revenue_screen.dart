import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

class AdminRevenueScreen extends StatefulWidget {
  const AdminRevenueScreen({super.key});
  @override
  State<AdminRevenueScreen> createState() => _AdminRevenueScreenState();
}

class _AdminRevenueScreenState extends State<AdminRevenueScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = {};
  Map<String, dynamic> _buckets = {};
  List<dynamic> _trend = [];
  DateTimeRange? _range;

  List<dynamic> _invoices = [];
  bool _invoicesLoading = true;
  String _invoiceStatus = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    setState(() => _invoicesLoading = true);
    try {
      final res = await _repo.invoices(status: _invoiceStatus);
      setState(() {
        _invoices = (res['data'] as List?) ?? [];
        _invoicesLoading = false;
      });
    } on AdminException catch (_) {
      setState(() => _invoicesLoading = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _repo.revenue(
        from: _range != null ? DateFormat('yyyy-MM-dd').format(_range!.start) : null,
        to: _range != null ? DateFormat('yyyy-MM-dd').format(_range!.end) : null,
      );
      final data = res['data'] as Map<String, dynamic>? ?? {};
      setState(() {
        _summary = (data['summary'] as Map<String, dynamic>?) ?? {};
        _buckets = (data['consultation_revenue_period_buckets'] as Map<String, dynamic>?) ?? {};
        _trend = (data['revenue_30d'] as List?) ?? [];
        _loading = false;
      });
    } on AdminException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  num _n(String k) => (_summary[k] as num?) ?? 0;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
        context: context, firstDate: DateTime(now.year - 2), lastDate: DateTime(now.year + 1), initialDateRange: _range);
    if (picked != null) {
      setState(() => _range = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/revenue',
      title: 'Billing / Revenue',
      actions: [
        TextButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range_rounded, size: 16),
            label: Text(_range == null
                ? 'Date range'
                : '${DateFormat('d MMM').format(_range!.start)} - ${DateFormat('d MMM').format(_range!.end)}')),
        if (_range != null)
          IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () {
                setState(() => _range = null);
                _load();
              }),
        IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
      ],
      child: _loading
          ? const Padding(padding: EdgeInsets.only(top: 100), child: Center(child: CircularProgressIndicator()))
          : _error != null
              ? AdminEmptyState(message: _error!)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AdminSectionCard(
                    title: 'Revenue Summary',
                    child: Column(children: [
                      Row(children: [
                        Expanded(child: AdminStatCard(label: 'Gross Revenue', value: fmtRupees(_n('gross_revenue')), icon: Icons.trending_up_rounded, color: kAdminGreen)),
                        const SizedBox(width: 12),
                        Expanded(child: AdminStatCard(label: 'Net Revenue', value: fmtRupees(_n('net_revenue')), icon: Icons.account_balance_wallet_rounded, color: kAdminAccent)),
                        const SizedBox(width: 12),
                        Expanded(child: AdminStatCard(label: 'Refunds', value: fmtRupees(_n('refund_amount')), icon: Icons.replay_rounded, color: kAdminRed)),
                        const SizedBox(width: 12),
                        Expanded(child: AdminStatCard(label: 'Successful Payments', value: '${_n('successful_consultation_payments') + _n('successful_subscription_payments')}', icon: Icons.check_circle_rounded, color: kAdminGreen)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: AdminStatCard(label: 'Lawyer Earnings (gross)', value: fmtRupees(_n('lawyer_earnings_gross')), icon: Icons.gavel_rounded, color: kAdminGold, subtitle: '100% — no commission split exists')),
                        const SizedBox(width: 12),
                        Expanded(child: AdminStatCard(label: 'Platform Revenue', value: fmtRupees(_n('platform_revenue')), icon: Icons.business_center_rounded, color: kAdminAccent, subtitle: 'Subscriptions + invoice platform fees')),
                        const SizedBox(width: 12),
                        Expanded(child: AdminStatCard(label: 'Firm Invoice Revenue', value: fmtRupees(_n('firm_invoice_revenue')), icon: Icons.receipt_long_rounded, color: kAdminGreen, subtitle: 'Service amount only, excl. GST/fee')),
                        const SizedBox(width: 12),
                        Expanded(child: AdminStatCard(label: 'GST Collected', value: fmtRupees(_n('gst_collected')), icon: Icons.receipt_rounded, color: kAdminAmber, subtitle: 'Pass-through — not platform revenue')),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  _invoicesSection(),
                  const SizedBox(height: 20),
                  AdminSectionCard(
                    title: 'Consultation Revenue by Period',
                    child: Row(children: [
                      Expanded(child: _bucketTile('Today', _buckets['today'])),
                      Expanded(child: _bucketTile('This Week', _buckets['week'])),
                      Expanded(child: _bucketTile('This Month', _buckets['month'])),
                      Expanded(child: _bucketTile('This Year', _buckets['year'])),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  AdminSectionCard(
                    title: 'Consultation Revenue — last 30 days',
                    child: SizedBox(
                      height: 90,
                      child: _trend.isEmpty
                          ? const AdminEmptyState()
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: _trend.map((d) {
                                final v = ((d['value'] as num?) ?? 0).toDouble();
                                final maxV = _trend
                                    .map((e) => ((e['value'] as num?) ?? 0).toDouble())
                                    .reduce((a, b) => a > b ? a : b)
                                    .clamp(1, double.infinity);
                                final h = (v / maxV) * 80 + 2;
                                return Expanded(
                                  child: Tooltip(
                                    message: '${d['date']}: ${fmtRupees(v)}',
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 1),
                                      child: Container(
                                          height: h,
                                          decoration: BoxDecoration(
                                              color: v > 0 ? kAdminGreen : kAdminBorder,
                                              borderRadius: BorderRadius.circular(2))),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No refund-issuing feature exists yet — refund figures reflect the schema being ready, not an active flow.',
                    style: const TextStyle(color: kAdminTextMuted, fontSize: 11.5, fontStyle: FontStyle.italic),
                  ),
                ]),
    );
  }

  Widget _bucketTile(String label, dynamic value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(fmtRupees(value as num?), style: const TextStyle(color: kAdminTextPri, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: kAdminTextMuted, fontSize: 11.5)),
      ]);

  /// Bills (invoices) with their full mandatory GST/platform-fee breakdown —
  /// reads straight from `invoices` (see AdminGetInvoices' doc comment) so
  /// every bill shows up here regardless of whether it was ever paid
  /// through Razorpay or the manual UPI/bank-transfer proof flow.
  Widget _invoicesSection() => AdminSectionCard(
        title: 'Invoices — GST & Platform Fee Breakdown',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, children: [
            for (final s in const [
              ('', 'All'),
              ('unpaid', 'Unpaid'),
              ('partial', 'Partial'),
              ('paid', 'Paid'),
              ('pending_verification', 'Pending Verification'),
            ])
              AdminFilterChip(
                  label: s.$2,
                  selected: _invoiceStatus == s.$1,
                  onTap: () {
                    setState(() => _invoiceStatus = s.$1);
                    _loadInvoices();
                  }),
          ]),
          const SizedBox(height: 14),
          if (_invoicesLoading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
          else if (_invoices.isEmpty)
            const AdminEmptyState()
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(kAdminBg),
                columns: const [
                  DataColumn(label: Text('Invoice #')),
                  DataColumn(label: Text('Lawyer')),
                  DataColumn(label: Text('Client')),
                  DataColumn(label: Text('Base Amount')),
                  DataColumn(label: Text('GST')),
                  DataColumn(label: Text('Platform Fee')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Paid')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Date')),
                ],
                rows: _invoices.map((inv) {
                  return DataRow(cells: [
                    DataCell(Text(inv['invoice_number'] ?? '')),
                    DataCell(Text((inv['lawyer_name'] ?? '').toString().isEmpty ? '—' : inv['lawyer_name'])),
                    DataCell(Text((inv['client_name'] ?? '').toString().isEmpty ? '—' : inv['client_name'])),
                    DataCell(Text(fmtRupees(inv['subtotal'] as num?))),
                    DataCell(Text(
                        '${fmtRupees(inv['gst_amount'] as num?)} (${(inv['gst_rate'] as num? ?? 0).toStringAsFixed(0)}%)',
                        style: const TextStyle(color: kAdminAmber))),
                    DataCell(Text(fmtRupees(inv['platform_fee'] as num?), style: const TextStyle(color: kAdminAccent))),
                    DataCell(Text(fmtRupees(inv['total_amount'] as num?), style: const TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(Text(fmtRupees(inv['paid_amount'] as num?), style: const TextStyle(color: kAdminGreen))),
                    DataCell(AdminBadge(inv['status'] ?? '', AdminBadge.colorFor(inv['status'] ?? ''))),
                    DataCell(Text(fmtDate(inv['created_at']))),
                  ]);
                }).toList(),
              ),
            ),
        ]),
      );
}
