import 'package:flutter/material.dart';

import '../repositories/invoice_payment_repository.dart';
import 'subscription_checkout_screen.dart' show CheckoutOutcome;

const _bg = Color(0xFFF0FAF6);
const _green = Color(0xFF0D6E4F);
const _textPri = Color(0xFF0A2E1F);
const _textMuted = Color(0xFF4A7A63);

/// Confirms an invoice payment with no payment gateway involved — Razorpay
/// checkout is turned off for clients for now (it was failing outright with
/// "Failed to create Razorpay order" and left no way through). One tap marks
/// the invoice paid and notifies the lawyer, exactly as a real payment would.
///
/// Kept as its own screen with the same constructor/[CheckoutOutcome]
/// contract the Razorpay version had, so every place that pushes this route
/// (the invoice list, the dashboard) needed no changes. The real Razorpay
/// flow this replaced is not deleted — see git history — reinstating it
/// later is swapping this screen's body back, not rebuilding call sites.
class InvoiceCheckoutScreen extends StatefulWidget {
  final String invoiceId;
  final double amount;
  final String invoiceNumber;

  const InvoiceCheckoutScreen({
    super.key,
    required this.invoiceId,
    required this.amount,
    required this.invoiceNumber,
  });

  @override
  State<InvoiceCheckoutScreen> createState() => _InvoiceCheckoutScreenState();
}

class _InvoiceCheckoutScreenState extends State<InvoiceCheckoutScreen> {
  final _repo = InvoicePaymentRepository();
  bool _settling = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _settling = true;
      _error = null;
    });
    try {
      await _repo.payWithoutGateway(widget.invoiceId);
      if (mounted) Navigator.pop(context, CheckoutOutcome.paid);
    } on InvoicePaymentException catch (e) {
      if (!mounted) return;
      setState(() {
        _settling = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_settling,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          title: const Text('Confirm payment', style: TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _settling
                ? null
                : () => Navigator.pop(context, CheckoutOutcome.cancelled),
          ),
        ),
        body: Stack(children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.receipt_long_rounded, size: 44, color: _green),
                const SizedBox(height: 16),
                Text(
                  'Invoice ${widget.invoiceNumber} — '
                  '₹${widget.amount.toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _textPri, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Confirming marks this invoice paid immediately and '
                  'notifies your lawyer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textMuted, fontSize: 13, height: 1.5),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFFD9534F), fontSize: 13, height: 1.4)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _settling ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Confirm Payment',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
          if (_settling) _buildSettling(),
        ]),
      ),
    );
  }

  Widget _buildSettling() => Container(
        color: _bg.withValues(alpha: 0.96),
        child: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: _green),
            SizedBox(height: 20),
            Text('Confirming your payment…',
                style: TextStyle(
                    color: _textPri, fontSize: 15, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('Please do not close this screen.',
                style: TextStyle(color: _textMuted, fontSize: 12)),
          ]),
        ),
      );
}
