import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownDark = Color(0xFF0B0726);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF1B1533);
const _textMuted = Color(0xFF7B7594);
const _success = Color(0xFF2E8B57);
const _error = Color(0xFFD9534F);
const _warning = Color(0xFFD4A017);
const _info = Color(0xFF4A90D9);

class BillingListScreen extends StatefulWidget {
  const BillingListScreen({super.key});
  @override
  State<BillingListScreen> createState() => _BillingListScreenState();
}

class _BillingListScreenState extends State<BillingListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<dynamic> _invoices = [];
  List<dynamic> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Future.wait([
        DioClient.instance.get('/invoices'),
        DioClient.instance.get('/payments'),
      ]);
      setState(() {
        _invoices = res[0].data['data'] ?? [];
        _payments = res[1].data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // ── Real calculations ─────────────────────
  double get _totalInvoiced => _invoices.fold(
      0.0, (s, i) => s + ((i['total_amount'] ?? 0.0) as num).toDouble());
  double get _totalPaid => _invoices.fold(
      0.0, (s, i) => s + ((i['paid_amount'] ?? 0.0) as num).toDouble());
  double get _totalPending => _totalInvoiced - _totalPaid;
  double get _totalTax => _invoices.fold(
      0.0, (s, i) => s + ((i['tax_amount'] ?? 0.0) as num).toDouble());
  int get _paidCount => _invoices.where((i) => i['status'] == 'paid').length;
  int get _unpaidCount => _invoices.where((i) => i['status'] != 'paid').length;
  int get _partialCount =>
      _invoices.where((i) => i['status'] == 'partial').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // ── Brown Header ──────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [_brown, _brownDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
          child: SafeArea(
              bottom: false,
              child: Column(children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => context.pop()),
                    const Expanded(
                        child: Text('Billing',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700))),
                    IconButton(
                      icon: const Icon(Icons.add_rounded,
                          color: Color(0xFFFFD700), size: 28),
                      onPressed: () =>
                          context.push('/billing/create').then((_) => _load()),
                    ),
                  ]),
                ),
                TabBar(
                  controller: _tabCtrl,
                  indicatorColor: const Color(0xFFFFD700),
                  indicatorWeight: 3,
                  labelColor: const Color(0xFFFFD700),
                  unselectedLabelColor: Colors.white60,
                  tabs: const [Tab(text: 'Invoices'), Tab(text: 'Payments')],
                ),
              ])),
        ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _brown))
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _InvoicesTab(
                      invoices: _invoices,
                      totalInvoiced: _totalInvoiced,
                      totalPaid: _totalPaid,
                      totalPending: _totalPending,
                      totalTax: _totalTax,
                      paidCount: _paidCount,
                      unpaidCount: _unpaidCount,
                      partialCount: _partialCount,
                      onRefresh: _load,
                    ),
                    _PaymentsTab(payments: _payments),
                  ],
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/billing/create').then((_) => _load()),
        backgroundColor: _brown,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New Invoice',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ── Invoices Tab ───────────────────────────────────
class _InvoicesTab extends StatefulWidget {
  final List<dynamic> invoices;
  final double totalInvoiced, totalPaid, totalPending, totalTax;
  final int paidCount, unpaidCount, partialCount;
  final VoidCallback onRefresh;
  const _InvoicesTab({
    required this.invoices,
    required this.totalInvoiced,
    required this.totalPaid,
    required this.totalPending,
    required this.totalTax,
    required this.paidCount,
    required this.unpaidCount,
    required this.partialCount,
    required this.onRefresh,
  });
  @override
  State<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends State<_InvoicesTab> {
  String _filter = 'all';

  List<dynamic> get _filtered {
    if (_filter == 'paid')
      return widget.invoices.where((i) => i['status'] == 'paid').toList();
    if (_filter == 'unpaid')
      return widget.invoices.where((i) => i['status'] == 'unpaid').toList();
    if (_filter == 'partial')
      return widget.invoices.where((i) => i['status'] == 'partial').toList();
    return widget.invoices;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _brown,
      backgroundColor: _bgCard,
      onRefresh: () async => widget.onRefresh(),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        // ── Summary Cards ──────────────────────
        Row(children: [
          Expanded(
              child: _SummaryCard('₹${widget.totalInvoiced.toStringAsFixed(0)}',
                  'Total Billed', _info, Icons.receipt_long_rounded)),
          const SizedBox(width: 8),
          Expanded(
              child: _SummaryCard('₹${widget.totalPaid.toStringAsFixed(0)}',
                  'Collected', _success, Icons.check_circle_rounded)),
          const SizedBox(width: 8),
          Expanded(
              child: _SummaryCard('₹${widget.totalPending.toStringAsFixed(0)}',
                  'Pending', _error, Icons.pending_rounded)),
        ]),
        const SizedBox(height: 10),

        // ── Tax summary ────────────────────────
        if (widget.totalTax > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: _bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border, width: 0.8)),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(children: [
                    Icon(Icons.percent_rounded, color: _warning, size: 16),
                    SizedBox(width: 6),
                    Text('Total Tax Collected',
                        style: TextStyle(color: _textMuted, fontSize: 12)),
                  ]),
                  Text('₹${widget.totalTax.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: _warning,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ]),
          ),
        const SizedBox(height: 14),

        // ── Collection rate ─────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border, width: 0.8)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Collection Rate',
                  style: TextStyle(
                      color: _textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              Text(
                widget.totalInvoiced > 0
                    ? '${((widget.totalPaid / widget.totalInvoiced) * 100).toStringAsFixed(1)}%'
                    : '0%',
                style: const TextStyle(
                    color: _brown, fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: widget.totalInvoiced > 0
                    ? (widget.totalPaid / widget.totalInvoiced).clamp(0.0, 1.0)
                    : 0.0,
                backgroundColor: _border,
                valueColor: const AlwaysStoppedAnimation(_success),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(
                  '${widget.paidCount} paid • ${widget.partialCount} partial • ${widget.unpaidCount} unpaid',
                  style: const TextStyle(color: _textMuted, fontSize: 10)),
              Text('${widget.invoices.length} total',
                  style: const TextStyle(color: _textMuted, fontSize: 10)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),

        // ── Filter pills ───────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _FilterPill('All (${widget.invoices.length})', 'all', _filter,
                (v) => setState(() => _filter = v)),
            const SizedBox(width: 8),
            _FilterPill('Paid (${widget.paidCount})', 'paid', _filter,
                (v) => setState(() => _filter = v)),
            const SizedBox(width: 8),
            _FilterPill('Partial (${widget.partialCount})', 'partial', _filter,
                (v) => setState(() => _filter = v)),
            const SizedBox(width: 8),
            _FilterPill('Unpaid (${widget.unpaidCount})', 'unpaid', _filter,
                (v) => setState(() => _filter = v)),
          ]),
        ),
        const SizedBox(height: 14),

        // ── Invoice list ───────────────────────
        ..._filtered.asMap().entries.map((e) => TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 200 + (e.key * 60)),
              builder: (_, v, child) => Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Transform.translate(
                      offset: Offset(0, 20 * (1 - v)), child: child)),
              child: _InvoiceCard(invoice: e.value, onReturn: widget.onRefresh),
            )),

        if (_filtered.isEmpty)
          Center(
              child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(children: [
              Icon(Icons.receipt_long_rounded,
                  color: _brown.withValues(alpha: 0.3), size: 48),
              const SizedBox(height: 12),
              const Text('No invoices found',
                  style: TextStyle(color: _textMuted, fontSize: 15)),
            ]),
          )),
        const SizedBox(height: 100),
      ]),
    );
  }
}

// ── Invoice Card ───────────────────────────────────
class _InvoiceCard extends StatelessWidget {
  final dynamic invoice;
  final VoidCallback onReturn;
  const _InvoiceCard({required this.invoice, required this.onReturn});

  @override
  Widget build(BuildContext context) {
    final status = invoice['status'] ?? 'unpaid';
    final isPaid = status == 'paid';
    final isPartial = status == 'partial';
    final total = ((invoice['total_amount'] ?? 0.0) as num).toDouble();
    final paid = ((invoice['paid_amount'] ?? 0.0) as num).toDouble();
    final tax = ((invoice['tax_amount'] ?? 0.0) as num).toDouble();
    final taxPct = ((invoice['tax_percent'] ?? 0.0) as num).toDouble();
    final subtotal = total - tax;
    final pending = total - paid;
    final paidPct = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'paid':
        statusColor = _success;
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'partial':
        statusColor = _warning;
        statusIcon = Icons.pending_rounded;
        break;
      default:
        statusColor = _error;
        statusIcon = Icons.cancel_rounded;
    }

    return GestureDetector(
      onTap: () => _showDetail(
          context, total, paid, tax, taxPct, subtotal, pending, status),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
                color: _brown.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(children: [
          // Top bar
          Container(
              height: 4,
              decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)))),

          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(children: [
              Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.receipt_long_rounded,
                      color: statusColor, size: 22)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(invoice['invoice_number'] ?? '',
                        style: const TextStyle(
                            color: _textPri,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    Text(invoice['client_name'] ?? '',
                        style:
                            const TextStyle(color: _textMuted, fontSize: 12)),
                  ])),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(statusIcon, color: statusColor, size: 12),
                  const SizedBox(width: 4),
                  Text(status.toUpperCase(),
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
          ),

          // Amount breakdown
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(children: [
              Divider(color: _border, height: 1, thickness: 0.6),
              const SizedBox(height: 10),

              // Subtotal row (if tax exists)
              if (tax > 0) ...[
                _AmtRow('Subtotal', '₹${subtotal.toStringAsFixed(2)}',
                    _textMuted, _textMuted),
                const SizedBox(height: 4),
                _AmtRow('Tax (${taxPct.toInt()}%)',
                    '+ ₹${tax.toStringAsFixed(2)}', _textMuted, _warning),
                const SizedBox(height: 4),
                Divider(color: _border, height: 8, thickness: 0.5),
              ],

              // Total
              _AmtRow('Total Amount', '₹${total.toStringAsFixed(2)}', _textPri,
                  _brown,
                  bold: true, valueLarge: true),
              const SizedBox(height: 6),

              // Paid / Pending
              if (isPaid) ...[
                _AmtRow('Amount Paid', '₹${paid.toStringAsFixed(2)}',
                    _textMuted, _success),
              ] else if (isPartial) ...[
                _AmtRow('Amount Paid', '₹${paid.toStringAsFixed(2)}',
                    _textMuted, _success),
                const SizedBox(height: 4),
                _AmtRow('Amount Pending', '₹${pending.toStringAsFixed(2)}',
                    _textMuted, _error),
              ] else ...[
                _AmtRow('Amount Due', '₹${pending.toStringAsFixed(2)}',
                    _textMuted, _error),
              ],

              // Progress bar
              const SizedBox(height: 10),
              ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: paidPct,
                    backgroundColor: _border,
                    valueColor: AlwaysStoppedAnimation(statusColor),
                    minHeight: 8,
                  )),
              const SizedBox(height: 5),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${(paidPct * 100).toInt()}% paid',
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
                Text(invoice['issue_date']?.toString().substring(0, 10) ?? '',
                    style: const TextStyle(color: _textMuted, fontSize: 10)),
              ]),

              // "Pay Now"/"Pay ₹X" was here — Lawyer Billing is a view of
              // what the Client owes/paid, not something the Lawyer pays
              // themselves. Tapping the card still opens the full detail
              // sheet below, which is where the payment proof is shown.
            ]),
          ),
        ]),
      ),
    );
  }

  void _showDetail(BuildContext context, double total, double paid, double tax,
      double taxPct, double subtotal, double pending, String status) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (_, ctrl) => ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: _border,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),

              // Invoice number + client
              Text(invoice['invoice_number'] ?? '',
                  style: const TextStyle(
                      color: _brown,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              Text(invoice['client_name'] ?? '',
                  style: const TextStyle(color: _textMuted, fontSize: 14)),
              const SizedBox(height: 20),

              // Full breakdown
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border)),
                child: Column(children: [
                  _DR(
                      'Invoice Date',
                      invoice['issue_date']?.toString().substring(0, 10) ??
                          '-'),
                  _DR('Due Date',
                      invoice['due_date']?.toString().substring(0, 10) ?? '-'),
                  _DR('Status', status.toUpperCase()),
                  Divider(color: _border, height: 16, thickness: 0.6),
                  _DR('Subtotal', '₹${subtotal.toStringAsFixed(2)}'),
                  if (tax > 0)
                    _DR('Tax (${taxPct.toInt()}%)',
                        '+ ₹${tax.toStringAsFixed(2)}',
                        valColor: _warning),
                  Divider(color: _border, height: 16, thickness: 0.6),
                  _DR('Total Amount', '₹${total.toStringAsFixed(2)}',
                      bold: true, valColor: _brown),
                  Divider(color: _border, height: 16, thickness: 0.6),
                  _DR('Amount Paid', '₹${paid.toStringAsFixed(2)}',
                      valColor: _success),
                  if (status != 'paid')
                    _DR('Amount Pending', '₹${pending.toStringAsFixed(2)}',
                        valColor: _error),
                ]),
              ),
              if ((invoice['notes'] ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Notes',
                            style: TextStyle(
                                color: _textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(invoice['notes'],
                            style:
                                const TextStyle(color: _textPri, height: 1.5)),
                      ]),
                ),
              ],
              const SizedBox(height: 40),
            ]),
      ),
    );
  }
}

Widget _AmtRow(String label, String value, Color labelColor, Color valueColor,
        {bool bold = false, bool valueLarge = false}) =>
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label,
          style: TextStyle(
              color: labelColor,
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      Text(value,
          style: TextStyle(
              color: valueColor,
              fontSize: valueLarge ? 17 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
    ]);

Widget _DR(String label, String value, {bool bold = false, Color? valColor}) =>
    Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: valColor ?? _textPri,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  fontSize: bold ? 16 : 13)),
        ]));

// ── Payments Tab ───────────────────────────────────
class _PaymentsTab extends StatelessWidget {
  final List<dynamic> payments;
  const _PaymentsTab({required this.payments});

  double get _totalPayments => payments.fold(
      0.0, (s, p) => s + ((p['amount'] ?? 0.0) as num).toDouble());

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.payments_rounded, color: _brown.withValues(alpha: 0.3), size: 48),
        const SizedBox(height: 12),
        const Text('No payments recorded',
            style: TextStyle(color: _textMuted, fontSize: 15)),
      ]));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Total payments card
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [_brown, _brownDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          const Icon(Icons.account_balance_wallet_rounded,
              color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Total Payments Received',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            Text('₹${_totalPayments.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 24)),
            Text('${payments.length} transactions',
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      ...payments.map((p) {
        final amount = ((p['amount'] ?? 0.0) as num).toDouble();
        final method = p['payment_method'] ?? 'Payment';
        final date = p['payment_date']?.toString().substring(0, 10) ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _success.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                  color: _brown.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(children: [
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: _success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.payments_rounded,
                    color: _success, size: 22)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(method,
                      style: const TextStyle(
                          color: _textPri,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  Text(date,
                      style: const TextStyle(color: _textMuted, fontSize: 12)),
                  if ((p['notes'] ?? '').isNotEmpty)
                    Text(p['notes'],
                        style: const TextStyle(color: _textMuted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ])),
            Text('₹${amount.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: _success,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
          ]),
        );
      }),
      const SizedBox(height: 80),
    ]);
  }
}

// ── Summary Card ───────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final String value, label;
  final Color color;
  final IconData icon;
  const _SummaryCard(this.value, this.label, this.color, this.icon);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                  color: _brown.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w800))),
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 10)),
        ]),
      );
}

// ── Filter Pill ────────────────────────────────────
class _FilterPill extends StatelessWidget {
  final String label, value, current;
  final Function(String) onTap;
  const _FilterPill(this.label, this.value, this.current, this.onTap);
  @override
  Widget build(BuildContext context) {
    final sel = current == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap(value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? _brown : _bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? _brown : _border),
          boxShadow: sel
              ? [BoxShadow(color: _brown.withValues(alpha: 0.2), blurRadius: 6)]
              : [],
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : _textMuted,
                fontSize: 12,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
      ),
    );
  }
}
