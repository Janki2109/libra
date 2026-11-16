import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../repositories/subscription_repository.dart';

const _bg = Color(0xFF0A0A14);
const _bgCard = Color(0xFF150A2E);
const _gold = Color(0xFFD4A017);
const _border = Color(0xFF2A1A4E);
const _textPri = Color(0xFFFFFFFF);
const _textMuted = Color(0xFF8888AA);
const _success = Color(0xFF2E8B57);

/// The payment confirmation screen for the DEMO payment flow.
///
/// Real payment gateway integration is not available yet. This is a real,
/// working substitute -- not a placeholder -- that actually activates a
/// subscription server-side, but it is clearly labelled DEMO throughout
/// (title, Payment Mode row, success message) and never asks for a card
/// number, UPI PIN, bank password or OTP anywhere on this screen, because
/// it never needs one: nothing here talks to a payment gateway at all.
class DemoPaymentScreen extends StatefulWidget {
  final Plan plan;
  final String billingCycle; // 'monthly' | 'yearly'

  const DemoPaymentScreen(
      {super.key, required this.plan, required this.billingCycle});

  @override
  State<DemoPaymentScreen> createState() => _DemoPaymentScreenState();
}

class _DemoPaymentScreenState extends State<DemoPaymentScreen> {
  final _repo = SubscriptionRepository();
  bool _paying = false;
  String? _error;

  double get _price => widget.billingCycle == 'yearly'
      ? widget.plan.priceYearly
      : widget.plan.priceMonthly;

  // Display-only estimate shown before paying -- the server computes the
  // authoritative start/expiry (which may extend an existing period
  // instead of starting fresh "today") and that real value is what the
  // success screen actually shows afterward.
  DateTime get _estimatedStart => DateTime.now();
  DateTime get _estimatedExpiry => widget.billingCycle == 'yearly'
      ? _estimatedStart.add(const Duration(days: 365))
      : _estimatedStart.add(const Duration(days: 30));

  String _fmt(DateTime d) => DateFormat('d MMM yyyy').format(d);

  Future<void> _payNow() async {
    setState(() {
      _paying = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    try {
      final result = await _repo.demoPay(
        plan: widget.plan.name,
        billingCycle: widget.billingCycle,
      );
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      await _showSuccess(result);
      if (mounted) Navigator.of(context).pop(true);
    } on BillingException catch (e) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        _error = e.message;
      });
    }
  }

  Future<void> _showSuccess(DemoPaymentResult result) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: _bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: _success, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text('Subscription Activated Successfully!',
                  style: TextStyle(
                      color: _textPri,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Plan', result.planName),
              _row('Amount', '₹${result.amount.toStringAsFixed(0)}'),
              _row('Valid Until', _fmt(result.expiryDate)),
              _row('Transaction ID', result.transactionId),
              const SizedBox(height: 8),
              const Text(
                'This was a DEMO payment. No real money was charged.',
                style: TextStyle(color: _textMuted, fontSize: 11),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Continue',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 12)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _textPri, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_paying,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bgCard,
          foregroundColor: _textPri,
          elevation: 0,
          title: const Text('Confirm Payment', style: TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _paying ? null : () => Navigator.of(context).pop(false),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _bgCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('DEMO PAYMENT',
                          style: TextStyle(
                              color: _gold, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _detailRow('Selected Plan', widget.plan.displayName),
                  _detailRow('Amount',
                      '₹${_price.toStringAsFixed(0)}'),
                  _detailRow('Billing Period',
                      widget.billingCycle == 'yearly' ? 'Yearly' : 'Monthly'),
                  const Divider(color: _border, height: 28),
                  _detailRow('Start Date (est.)', _fmt(_estimatedStart)),
                  _detailRow('Expiry Date (est.)', _fmt(_estimatedExpiry)),
                  const SizedBox(height: 4),
                  const Text(
                    'Final dates are confirmed by the server once payment completes.',
                    style: TextStyle(color: _textMuted, fontSize: 11),
                  ),
                  const Divider(color: _border, height: 28),
                  _detailRow('Payment Mode', 'Demo Payment'),
                ]),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: const Row(children: [
                  Icon(Icons.info_outline_rounded, color: _gold, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This is a demo payment. No real money will be charged, '
                      'and no card, UPI or bank details are collected.',
                      style: TextStyle(color: _textMuted, fontSize: 11.5),
                    ),
                  ),
                ]),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: Color(0xFFD9534F), fontSize: 12)),
              ],
              const Spacer(),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _paying ? null : () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(color: _textMuted, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _paying ? null : _payNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      disabledBackgroundColor: _gold.withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _paying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : const Text('Pay Now',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: _textPri, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}
