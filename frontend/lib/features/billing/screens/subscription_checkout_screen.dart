import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../repositories/subscription_repository.dart';

const _bg = Color(0xFFF5ECD7);
const _brown = Color(0xFF5C3317);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF8B5E3C);

/// Result handed back to the caller when this screen closes.
enum CheckoutOutcome { paid, cancelled, failed }

/// Hosts Razorpay's standard checkout.
///
/// The app has no native Razorpay SDK, and the paywall previously had no
/// payment path at all — its "subscribe" button showed bank details to copy by
/// hand and its confirm button granted a subscription locally with no money
/// involved. Razorpay's checkout.js is a supported browser integration, and
/// webview_flutter is already a dependency, so this is a real payment flow with
/// nothing new to add.
///
/// Nothing here is trusted. The page reports back an order id, payment id and
/// signature; the server recomputes that signature against its own secret
/// before it will activate anything, and receives the same event over a
/// webhook independently.
class SubscriptionCheckoutScreen extends StatefulWidget {
  final Checkout checkout;
  final String customerName;
  final String customerEmail;
  final String customerPhone;

  const SubscriptionCheckoutScreen({
    super.key,
    required this.checkout,
    this.customerName = '',
    this.customerEmail = '',
    this.customerPhone = '',
  });

  @override
  State<SubscriptionCheckoutScreen> createState() =>
      _SubscriptionCheckoutScreenState();
}

class _SubscriptionCheckoutScreenState
    extends State<SubscriptionCheckoutScreen> {
  final _repo = SubscriptionRepository();

  // Not initialised on web — see initState.
  late final WebViewController _controller;
  bool _loading = true;
  bool _settling = false;
  String? _error;
  // Guards against the page firing both a success and a dismiss callback, which
  // would otherwise pop the route twice.
  bool _finished = false;

  @override
  void initState() {
    super.initState();

    // webview_flutter ships no web implementation — constructing a
    // WebViewController in a browser build throws, which would have crashed
    // this screen the moment a user clicked Subscribe on the web target.
    // Razorpay's own hosted page handles the browser case instead.
    if (kIsWeb) {
      _loading = false;
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_bg)
      ..addJavaScriptChannel('LibraCheckout',
          onMessageReceived: (msg) => _onCheckoutMessage(msg.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (err) {
          // A sub-resource failure (font, analytics, ad-script Razorpay's
          // own checkout.js pulls in) is not the checkout page failing —
          // only a confirmed main-frame failure should end the flow.
          // Many Android WebView versions report `null` (not `false`) for a
          // sub-resource failure. Only a confirmed main-frame failure should
          // end the flow.
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
          await _repo.activate(
            orderId: msg['order_id'] as String? ?? '',
            paymentId: msg['payment_id'] as String? ?? '',
            signature: msg['signature'] as String? ?? '',
          );
          if (mounted) Navigator.pop(context, CheckoutOutcome.paid);
        } on BillingException catch (e) {
          // The payment itself succeeded — the webhook will still activate it
          // server-side — so this must not read as "your payment failed".
          if (!mounted) return;
          setState(() {
            _settling = false;
            _error = '${e.message}\n\nYour payment went through. '
                'If the plan does not appear in a minute, pull to refresh.';
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
  /// quotes: a customer name containing an apostrophe would otherwise break out
  /// of the string literal and corrupt the script.
  String _checkoutHtml() {
    final options = jsonEncode({
      'key': widget.checkout.keyId,
      'amount': widget.checkout.amountPaise,
      'currency': widget.checkout.currency,
      'order_id': widget.checkout.orderId,
      'name': 'Libra Law',
      'description': '${widget.checkout.planName} '
          '(${widget.checkout.billingCycle == 'yearly' ? 'yearly' : 'monthly'})',
      'prefill': {
        'name': widget.customerName,
        'email': widget.customerEmail,
        'contact': widget.customerPhone,
      },
      'theme': {'color': '#5C3317'},
      'retry': {'enabled': false},
    });

    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <style>
    html, body { margin:0; padding:0; height:100%; background:#F5ECD7;
                 font-family:-apple-system,Roboto,sans-serif; }
    #msg { display:flex; height:100%; align-items:center; justify-content:center;
           color:#8B5E3C; font-size:14px; text-align:center; padding:24px; }
  </style>
  <script src="https://checkout.razorpay.com/v1/checkout.js"></script>
</head>
<body>
  <div id="msg">Opening secure payment&hellip;</div>
  <script>
    function report(payload) {
      try { LibraCheckout.postMessage(JSON.stringify(payload)); } catch (e) {}
    }

    // checkout.js is loaded from the network; if it never arrives, say so
    // rather than sitting on "Opening secure payment" forever.
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

      // Fires when the user closes the sheet without paying.
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

  @override
  Widget build(BuildContext context) {
    // The back gesture must report a cancellation, not just vanish, or the
    // paywall behind has no idea what happened.
    return PopScope(
      canPop: !_settling,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_finished) _finished = true;
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _brown,
          foregroundColor: Colors.white,
          title: const Text('Secure payment', style: TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            // Disabled mid-settlement: closing while the activation call is in
            // flight would leave the user unsure whether they had paid.
            onPressed: _settling
                ? null
                : () => Navigator.pop(context, CheckoutOutcome.cancelled),
          ),
        ),
        body: Stack(children: [
          if (_error != null)
            _buildError()
          else if (kIsWeb)
            _buildWebCheckout()
          else
            WebViewWidget(controller: _controller),
          if (_loading && _error == null && !kIsWeb)
            const Center(child: CircularProgressIndicator(color: _brown)),
          if (_settling) _buildSettling(),
        ]),
      ),
    );
  }

  /// Browser fallback.
  ///
  /// The in-app sheet needs a WebView, which does not exist on web. Razorpay
  /// serves a hosted checkout for exactly this case, so the browser build hands
  /// the order off to it. The order id and amount were both fixed server-side
  /// when the order was created, so nothing about the price is negotiable here
  /// either.
  Widget _buildWebCheckout() {
    final url = Uri.parse(
      'https://api.razorpay.com/v1/checkout/embedded'
      '?key_id=${Uri.encodeQueryComponent(widget.checkout.keyId)}'
      '&order_id=${Uri.encodeQueryComponent(widget.checkout.orderId)}',
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline_rounded, size: 44, color: _brown),
          const SizedBox(height: 16),
          Text(
            '${widget.checkout.planName} — '
            '₹${widget.checkout.amountRupees.toStringAsFixed(0)}'
            '${widget.checkout.billingCycle == 'yearly' ? '/year' : '/month'}',
            style: const TextStyle(
                color: _textPri, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text(
            'Payment opens in a new tab. Come back here once it completes — '
            'your plan activates automatically.',
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
              backgroundColor: _brown,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Continue to payment',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          TextButton(
            // The webhook activates the subscription regardless of whether the
            // user makes it back to this screen, so re-checking is all this
            // needs to do.
            onPressed: () => Navigator.pop(context, CheckoutOutcome.paid),
            child: const Text("I've completed payment",
                style: TextStyle(color: _brown, fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 44, color: _brown),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _textPri, fontSize: 14, height: 1.5)),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, CheckoutOutcome.failed),
              child: const Text('Close',
                  style: TextStyle(
                      color: _brown, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );

  Widget _buildSettling() => Container(
        color: _bg.withValues(alpha: 0.96),
        child: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: _brown),
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
