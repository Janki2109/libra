import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../repositories/earnings_repository.dart';

// Same palette as the rest of the Lawyer Panel (dashboard_screen.dart,
// consultation_management_screen.dart, profile_screen.dart) — kept identical
// so this screen looks like it belongs, not a new design.
const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownDark = Color(0xFF0B0726);
const _gold = Color(0xFFD4AF37);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF1B1533);
const _textMuted = Color(0xFF7B7594);
const _green = Color(0xFF2E8B57);
const _red = Color(0xFFD9534F);
const _blue = Color(0xFF4A90D9);

/// The lawyer's Billing tab — a read-only ledger of consultation earnings.
/// Reuses the existing consultation-payment data (payment_status,
/// amount_paise, razorpay_payment_id on `consultations`, populated by the
/// existing Razorpay checkout/verify flow) via the new
/// GET /consultations/earnings endpoint. Nothing about the payment or
/// booking flow itself changes here — this only displays what already
/// happened.
class LawyerEarningsScreen extends StatefulWidget {
  const LawyerEarningsScreen({super.key});
  @override
  State<LawyerEarningsScreen> createState() => _LawyerEarningsScreenState();
}

class _LawyerEarningsScreenState extends State<LawyerEarningsScreen> {
  final _repo = EarningsRepository();

  bool _loading = true;
  String? _error;
  EarningsSummary _summary = EarningsSummary.empty;
  List<EarningsTransaction> _transactions = [];

  String _statusFilter = 'all'; // all | paid | pending | refunded
  DateTimeRange? _dateRange;

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
      final result = await _repo.fetch(
        status: _statusFilter,
        from: _dateRange != null ? DateFormat('yyyy-MM-dd').format(_dateRange!.start) : null,
        to: _dateRange != null ? DateFormat('yyyy-MM-dd').format(_dateRange!.end) : null,
      );
      if (!mounted) return;
      setState(() {
        _summary = result.summary;
        _transactions = result.transactions;
        _loading = false;
      });
    } on EarningsException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: _brown)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _load();
    }
  }

  void _clearDateRange() {
    setState(() => _dateRange = null);
    _load();
  }

  void _setFilter(String status) {
    if (status == _statusFilter) return;
    setState(() => _statusFilter = status);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [_brown, _brownDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
          child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 16),
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
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white),
                      onPressed: _load),
                ]),
              )),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _brown))
              : _error != null
                  ? _buildError()
                  : RefreshIndicator(
                      color: _brown,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildSummaryGrid(),
                          const SizedBox(height: 20),
                          _buildFilters(),
                          const SizedBox(height: 16),
                          _buildTransactionsHeader(),
                          const SizedBox(height: 10),
                          if (_transactions.isEmpty)
                            _buildEmpty()
                          else
                            ..._transactions.map((t) => _TransactionCard(t)),
                        ],
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 44, color: _red),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textPri, fontSize: 14, height: 1.5)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _brown,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ]),
        ),
      );

  Widget _buildEmpty() => Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(children: [
          Icon(Icons.receipt_long_rounded,
              color: _brown.withValues(alpha: 0.3), size: 56),
          const SizedBox(height: 12),
          const Text('No transactions yet',
              style: TextStyle(color: _textMuted, fontSize: 14)),
        ]),
      );

  Widget _buildSummaryGrid() {
    final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.65,
      children: [
        _StatCard('Total Earnings', f.format(_summary.totalEarnings),
            Icons.account_balance_wallet_rounded, _green),
        _StatCard('Total Received', f.format(_summary.totalReceived),
            Icons.savings_rounded, _blue),
        _StatCard('Pending Payments', f.format(_summary.pendingAmount),
            Icons.hourglass_top_rounded, _gold,
            subtitle: '${_summary.pendingPayments} txn'),
        _StatCard('Completed Payments', '${_summary.completedPayments}',
            Icons.check_circle_rounded, _green,
            subtitle: 'of ${_summary.totalTransactions} total'),
        _StatCard('Refunded Payments', f.format(_summary.refundedAmount),
            Icons.replay_rounded, _red,
            subtitle: '${_summary.refundedPayments} txn'),
        _StatCard('Transactions', '${_summary.totalTransactions}',
            Icons.receipt_long_rounded, _brown),
      ],
    );
  }

  Widget _buildFilters() {
    final chips = const [
      ('all', 'All'),
      ('paid', 'Paid'),
      ('pending', 'Pending'),
      ('refunded', 'Refunded'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final c in chips) ...[
            _FilterChip(c.$2, _statusFilter == c.$1, () => _setFilter(c.$1)),
            const SizedBox(width: 8),
          ],
          GestureDetector(
            onTap: _pickDateRange,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _dateRange != null ? _brown.withValues(alpha: 0.1) : _bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _dateRange != null ? _brown : _border,
                    width: _dateRange != null ? 1.3 : 0.8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.date_range_rounded,
                    color: _dateRange != null ? _brown : _textMuted, size: 14),
                const SizedBox(width: 6),
                Text(
                    _dateRange == null
                        ? 'Date'
                        : '${DateFormat('d MMM').format(_dateRange!.start)} - ${DateFormat('d MMM').format(_dateRange!.end)}',
                    style: TextStyle(
                        color: _dateRange != null ? _brown : _textMuted,
                        fontSize: 12,
                        fontWeight: _dateRange != null ? FontWeight.w700 : FontWeight.w400)),
                if (_dateRange != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                      onTap: _clearDateRange,
                      child: const Icon(Icons.close_rounded, color: _brown, size: 14)),
                ],
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildTransactionsHeader() => Row(children: [
        const Text('Transaction History',
            style: TextStyle(color: _textPri, fontSize: 15, fontWeight: FontWeight.w800)),
        const Spacer(),
        Text('${_transactions.length} shown',
            style: const TextStyle(color: _textMuted, fontSize: 12)),
      ]);
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color, {this.subtitle});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border, width: 0.8),
          boxShadow: [
            BoxShadow(
                color: _brown.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, color: color, size: 16)),
            const Spacer(),
          ]),
          const SizedBox(height: 8),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _textPri, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
          if (subtitle != null)
            Text(subtitle!,
                style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _brown : _bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? _brown : _border, width: 0.8),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : _textMuted,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
        ),
      );
}

class _TransactionCard extends StatelessWidget {
  final EarningsTransaction t;
  const _TransactionCard(this.t);

  Color get _statusColor => switch (t.paymentStatus) {
        'paid' => _green,
        'refunded' => _red,
        'failed' => _red,
        _ => _gold,
      };

  IconData get _typeIcon {
    final type = t.consultationType.toLowerCase();
    if (type.contains('video')) return Icons.videocam_rounded;
    if (type.contains('audio')) return Icons.phone_rounded;
    if (type.contains('office')) return Icons.business_center_rounded;
    return Icons.chat_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final date = t.paidAt ?? t.createdAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _statusColor.withValues(alpha: 0.2), width: 0.8),
        boxShadow: [
          BoxShadow(
              color: _brown.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(_typeIcon, color: _statusColor, size: 18)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.clientName,
                style: const TextStyle(
                    color: _textPri, fontWeight: FontWeight.w700, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(t.consultationType.isNotEmpty ? t.consultationType : 'Consultation',
                style: const TextStyle(color: _textMuted, fontSize: 12)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${t.amountRupees.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: _textPri, fontWeight: FontWeight.w800, fontSize: 15)),
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(t.paymentStatus.toUpperCase(),
                  style: TextStyle(
                      color: _statusColor, fontSize: 9, fontWeight: FontWeight.w800)),
            ),
          ]),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
              color: _bg, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border, width: 0.6)),
          child: Wrap(spacing: 14, runSpacing: 4, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.calendar_today_rounded, color: _brown, size: 12),
              const SizedBox(width: 5),
              Text(DateFormat('d MMM yyyy').format(date),
                  style: const TextStyle(color: _textPri, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
            if (t.razorpayPaymentId.isNotEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.tag_rounded, color: _brown, size: 12),
                const SizedBox(width: 4),
                Text(t.razorpayPaymentId,
                    style: const TextStyle(color: _textMuted, fontSize: 10)),
              ]),
            if (t.paymentMethod.isNotEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.credit_card_rounded, color: _brown, size: 12),
                const SizedBox(width: 4),
                Text(t.paymentMethod,
                    style: const TextStyle(color: _textMuted, fontSize: 10)),
              ]),
          ]),
        ),
      ]),
    );
  }
}
