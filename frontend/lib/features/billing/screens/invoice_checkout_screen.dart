import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../auth/providers/auth_provider.dart';
import '../repositories/invoice_payment_repository.dart';
import 'subscription_checkout_screen.dart' show CheckoutOutcome;

const _bg = Color(0xFFF0FAF6);
const _green = Color(0xFF0D6E4F);
const _textPri = Color(0xFF0A2E1F);
const _textMuted = Color(0xFF4A7A63);

/// Hosts Razorpay's standard checkout for paying an invoice online.
///
/// This is what "Pay Now" now opens instead of the manual UPI/bank-transfer
/// screen (PaymentScreen) — the app already has a real Razorpay integration
/// (subscription checkout, consultation checkout use it) and an invoice was
/// the one payment surface still routed straight to the manual proof-upload
/// flow. Deliberately its own screen rather than a reuse of
/// SubscriptionCheckoutScreen/ConsultationCheckoutScreen — same mechanism
/// (checkout.js in a WebView, a hosted-checkout fallback on web, nothing
/// trusted from the page without server-side signature verification), but
/// each of those describes a different kind of purchase. The manual UPI/
/// bank-transfer + payment-proof-upload flow is preserved unchanged and
/// reachable from here as a fallback (see "Pay manually" below), never
/// removed.
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

  InvoiceCheckout? _checkout;
  // Not initialised until the order exists — see _startOrder.
  WebViewController? _controller;

  bool _creatingOrder = true;
  bool _loading = true;
  bool _settling = false;
  String? _error;
  // Guards against the page firing both a success and a dismiss callback,
  // which would otherwise pop the route twice.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _startOrder();
  }

  Future<void> _startOrder() async {
    try {
      final checkout = await _repo.startCheckout(
        invoiceId: widget.invoiceId,
        invoiceNumber: widget.invoiceNumber,
      );
      if (!mounted) return;
      setState(() {
        _checkout = checkout;
        _creatingOrder = false;
      });
      _initWebView();
    } on InvoicePaymentException catch (e) {
      if (!mounted) return;
      setState(() {
        _creatingOrder = false;
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _initWebView() {
    // webview_flutter ships no web implementation — constructing a
    // WebViewController in a browser build throws. Razorpay's own hosted
    // page handles the browser case instead (see _buildWebCheckout).
    if (kIsWeb) {
      setState(() => _loading = false);
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_bg)
      ..addJavaScriptChannel('LibraInvoiceCheckout',
          onMessageReceived: (msg) => _onCheckoutMessage(msg.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (err) {
          // A sub-resource failure (font, analytics, ad-script Razorpay's own
          // checkout.js pulls in) is not the checkout page itself failing —
          // only a confirmed main-frame failure should end the flow. Many
          // Android WebView versions report `null` (not `false`) for a
          // sub-resource failure.
          if (err.isForMainFrame != true) return;
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = 'Could not load the payment page. '
                'Check your connection and try again.';
          });
        },
      ))
      ..loadHtmlString(_checkoutHtml(), baseUrl: 'https://checkout.razorpay.com');
  }

  /// The page posts a single JSON message back through the channel.
  Future<void> _onCheckoutMessage(String raw) async {
    if (_finished) return;

    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (msg['type']) {
      case 'success':
        _finished = true;
        setState(() => _settling = true);
        try {
          await _repo.verifyPayment(
            orderId: msg['order_id'] as String? ?? '',
            paymentId: msg['payment_id'] as String? ?? '',
            signature: msg['signature'] as String? ?? '',
          );
          if (mounted) Navigator.pop(context, CheckoutOutcome.paid);
        } on InvoicePaymentException catch (e) {
          if (!mounted) return;
          setState(() {
            _settling = false;
            _error = e.message;
          });
        }
        break;

      case 'dismissed':
        _finished = true;
        if (mounted) Navigator.pop(context, CheckoutOutcome.cancelled);
        break;

      case 'failed':
        _finished = true;
        if (!mounted) return;
        setState(() {
          _error = (msg['description'] as String?)?.trim().isNotEmpty == true
              ? msg['description'] as String
              : 'The payment could not be completed.';
        });
        break;
    }
  }

  /// Builds the checkout page.
  ///
  /// Every interpolated value is JSON-encoded rather than pasted between
  /// quotes: a name containing an apostrophe would otherwise break out of
  /// the string literal and corrupt the script.
  String _checkoutHtml() {
    final auth = context.read<AuthProvider>().user;
    final checkout = _checkout!;
    final options = jsonEncode({
      'key': checkout.keyId,
      'amount': checkout.amountPaise,
      'currency': checkout.currency,
      'order_id': checkout.orderId,
      'name': 'Libra Law',
      'description': 'Invoice ${checkout.invoiceNumber}',
      'prefill': {
        'name': auth?.name ?? '',
        'email': auth?.email ?? '',
        'contact': auth?.phone ?? '',
      },
      'theme': {'color': '#0D6E4F'},
      'retry': {'enabled': false},
    });

    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <style>
    html, body { margin:0; padding:0; height:100%; background:#F0FAF6;
                 font-family:-apple-system,Roboto,sans-serif; }
    #msg { display:flex; height:100%; align-items:center; justify-content:center;
           color:#4A7A63; font-size:14px; text-align:center; padding:24px; }
  </style>
  <script src="https://checkout.razorpay.com/v1/checkout.js"></script>
</head>
<body>
  <div id="msg">Opening secure payment&hellip;</div>
  <script>
    function report(payload) {
      try { LibraInvoiceCheckout.postMessage(JSON.stringify(payload)); } catch (e) {}
    }

    if (typeof Razorpay === 'undefined') {
      document.getElementById('msg').textContent =
        'Could not reach the payment provider. Check your connection.';
      report({ type: 'failed', description: 'Payment library failed to load.' });
    } else {
      var options = $options;

      options.handler = function (response) {
        report({
          type: 'success',
          order_id: response.razorpay_order_id,
          payment_id: response.razorpay_payment_id,
          signature: response.razorpay_signature
        });
      };

      options.modal = {
        ondismiss: function () { report({ type: 'dismissed' }); },
        escape: false
      };

      var rzp = new Razorpay(options);

      rzp.on('payment.failed', function (resp) {
        var d = (resp && resp.error && resp.error.description) || '';
        report({ type: 'failed', description: d });
      });

      rzp.open();
    }
  </script>
</body>
</html>
''';
  }

  void _payManually() {
    context.pushReplacement(
      '/billing/pay-manual/${widget.invoiceId}'
      '?amount=${widget.amount}&invoice=${Uri.encodeComponent(widget.invoiceNumber)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    // The back gesture must report a cancellation, not just vanish, or the
    // invoice screen behind has no idea what happened.
    return PopScope(
      canPop: !_settling,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_finished) _finished = true;
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          title: const Text('Secure payment', style: TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _settling
                ? null
                : () => Navigator.pop(context, CheckoutOutcome.cancelled),
          ),
        ),
        body: Stack(children: [
          if (_creatingOrder)
            const Center(child: CircularProgressIndicator(color: _green))
          else if (_error != null)
            _buildError()
          else if (kIsWeb)
            _buildWebCheckout()
          else if (_controller != null)
            WebViewWidget(controller: _controller!),
          if (_loading &&
              _error == null &&
              !_creatingOrder &&
              !kIsWeb)
            const Center(child: CircularProgressIndicator(color: _green)),
          if (_settling) _buildSettling(),
        ]),
        bottomNavigationBar: (_creatingOrder || _settling || _error != null)
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: TextButton(
                    onPressed: _payManually,
                    child: const Text(
                        'Having trouble? Pay via UPI / Bank Transfer manually',
                        style: TextStyle(color: _textMuted, fontSize: 12.5)),
                  ),
                ),
              ),
      ),
    );
  }

  /// Browser fallback: Razorpay's hosted checkout in a new tab, since
  /// webview_flutter has no web implementation. The order id and amount were
  /// both fixed server-side when the order was opened.
  Widget _buildWebCheckout() {
    final checkout = _checkout!;
    final url = Uri.parse(
      'https://api.razorpay.com/v1/checkout/embedded'
      '?key_id=${Uri.encodeQueryComponent(checkout.keyId)}'
      '&order_id=${Uri.encodeQueryComponent(checkout.orderId)}',
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline_rounded, size: 44, color: _green),
          const SizedBox(height: 16),
          Text(
            'Invoice ${checkout.invoiceNumber} — '
            '₹${checkout.amountRupees.toStringAsFixed(2)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _textPri, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text(
            'Payment opens in a new tab. Come back here once it completes — '
            'your invoice updates automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textMuted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async {
              if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                if (!mounted) return;
                setState(() => _error = 'Could not open the payment page.');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Continue to payment',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context, CheckoutOutcome.paid),
            child: const Text("I've completed payment",
                style: TextStyle(color: _green, fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 44, color: _green),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _textPri, fontSize: 14, height: 1.5)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _payManually,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Pay via UPI / Bank Transfer instead',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context, CheckoutOutcome.failed),
              child: const Text('Close',
                  style:
                      TextStyle(color: _green, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );

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
