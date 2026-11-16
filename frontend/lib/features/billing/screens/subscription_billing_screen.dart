import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/services/dio_client.dart';
import '../repositories/subscription_repository.dart';

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _navy = Color(0xFF150E3D);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF1B1533);
const _textMuted = Color(0xFF7B7594);
const _gold = Color(0xFFD4A017);
const _success = Color(0xFF2E8B57);
const _errColor = Color(0xFFD9534F);

/// "Subscription & Billing" -- Current Subscription + Subscription/Payment
/// History, all read from the backend (GET /subscription,
/// GET /subscription/payments). Every row in the history already comes
/// from subscription_payments and is never deleted when a new plan is
/// purchased, so a new purchase after expiry simply adds to this list
/// rather than replacing anything in it.
class SubscriptionBillingScreen extends StatefulWidget {
  const SubscriptionBillingScreen({super.key});
  @override
  State<SubscriptionBillingScreen> createState() =>
      _SubscriptionBillingScreenState();
}

class _SubscriptionBillingScreenState
    extends State<SubscriptionBillingScreen> {
  final _repo = SubscriptionRepository();
  Map<String, dynamic>? _current;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String? _error;

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
      final results = await Future.wait([
        DioClient.instance.get('/subscription'),
        _repo.fetchPaymentHistory(),
      ]);
      if (!mounted) return;
      setState(() {
        _current = (results[0] as dynamic).data['data'] as Map<String, dynamic>?;
        _history = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = DioClient.describeError(e);
      });
    }
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '—';
    final d = DateTime.tryParse(v.toString());
    if (d == null) return '—';
    return DateFormat('d MMM yyyy').format(d.toLocal());
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return _success;
      case 'trial':
        return _gold;
      default:
        return _errColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Subscription & Billing'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  color: _gold,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildCurrentSubscription(),
                      const SizedBox(height: 20),
                      const Text('Subscription & Payment History',
                          style: TextStyle(
                              color: _textPri,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      if (_history.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text('No payments yet',
                                style:
                                    const TextStyle(color: _textMuted, fontSize: 13)),
                          ),
                        )
                      else
                        ..._history.map(_buildHistoryCard),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, color: _textMuted, size: 44),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textPri, fontSize: 13)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ]),
        ),
      );

  Widget _buildCurrentSubscription() {
    final c = _current ?? {};
    final status = (c['status'] ?? 'none').toString();
    final isActive = c['is_active'] == true;
    final planName = (c['plan_name'] ?? '').toString();
    final amount = (c['amount'] as num?)?.toDouble();
    final cycle = (c['billing_cycle'] ?? '').toString();
    final daysRemaining = (c['days_remaining'] as num?)?.toInt() ?? 0;
    final startedAt = c['started_at'];
    final periodEnd = c['current_period_end'] ?? c['trial_ends_at'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF150E3D), Color(0xFF3D2C8D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('Current Subscription',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10)),
            child: Text(status.toUpperCase(),
                style: TextStyle(
                    color: _statusColor(status) == _success
                        ? const Color(0xFF8CFFC1)
                        : (_statusColor(status) == _gold ? _gold : const Color(0xFFFF9999)),
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 14),
        if (planName.isNotEmpty)
          Text(planName,
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        if (amount != null && amount > 0) ...[
          const SizedBox(height: 2),
          Text(
              '₹${amount.toStringAsFixed(0)}${cycle == 'yearly' ? '/year' : cycle == 'monthly' ? '/month' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: _statCol('Purchased', startedAt != null ? _fmtDate(startedAt) : '—')),
          Expanded(
              child: _statCol('Expires', periodEnd != null ? _fmtDate(periodEnd) : '—')),
          Expanded(
              child: _statCol('Remaining',
                  isActive ? '$daysRemaining day${daysRemaining == 1 ? '' : 's'}' : '—')),
        ]),
      ]),
    );
  }

  Widget _statCol(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      );

  Widget _buildHistoryCard(Map<String, dynamic> p) {
    final planName = (p['plan_name'] ?? '').toString();
    final amount = (p['amount'] as num?)?.toDouble() ?? 0;
    final cycle = (p['billing_cycle'] ?? '').toString();
    final paymentId = (p['payment_id'] ?? '').toString();
    final status = (p['status'] ?? '').toString();
    final mode = (p['payment_mode'] ?? '').toString();
    final periodStart = p['period_start'];
    final periodEnd = p['period_end'];
    final createdAt = p['created_at'];

    final now = DateTime.now();
    final endDate = periodEnd != null ? DateTime.tryParse(periodEnd.toString()) : null;
    final isExpired = endDate != null && endDate.isBefore(now);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(planName.isEmpty ? 'Plan' : planName,
                  style: const TextStyle(
                      color: _textPri, fontWeight: FontWeight.w700, fontSize: 14))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: (isExpired ? _textMuted : _success).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(isExpired ? 'EXPIRED' : 'ACTIVE',
                style: TextStyle(
                    color: isExpired ? _textMuted : _success,
                    fontSize: 10,
                    fontWeight: FontWeight.w800)),
          ),
          if (mode == 'demo') ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('DEMO',
                  style: TextStyle(color: _gold, fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Text('₹${amount.toStringAsFixed(0)}'
            '${cycle.isNotEmpty ? ' • ${cycle[0].toUpperCase()}${cycle.substring(1)}' : ''}'
            '${status.isNotEmpty ? ' • ${status[0].toUpperCase()}${status.substring(1)}' : ''}',
            style: const TextStyle(color: _textMuted, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
            'Purchased ${_fmtDate(createdAt)}'
            '${periodStart != null ? ' • Started ${_fmtDate(periodStart)}' : ''}'
            '${periodEnd != null ? ' • Expires ${_fmtDate(periodEnd)}' : ''}',
            style: const TextStyle(color: _textMuted, fontSize: 11)),
        if (paymentId.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Transaction ID: $paymentId',
              style: const TextStyle(
                  color: _textMuted, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}
