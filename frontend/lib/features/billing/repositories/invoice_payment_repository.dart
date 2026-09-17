import 'package:dio/dio.dart';

import '../../../core/services/dio_client.dart';

/// A Razorpay order opened to pay an invoice's remaining balance online.
class InvoiceCheckout {
  final String invoiceId;
  final String invoiceNumber;
  final String orderId;
  final int amountPaise;
  final double amountRupees;
  final String currency;
  final String keyId;

  const InvoiceCheckout({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.orderId,
    required this.amountPaise,
    required this.amountRupees,
    required this.currency,
    required this.keyId,
  });

  factory InvoiceCheckout.fromJson(
      String invoiceNumber, Map<String, dynamic> json) {
    final paise = (json['amount'] as num?)?.toInt() ?? 0;
    return InvoiceCheckout(
      invoiceId: json['invoice_id'] as String? ?? '',
      invoiceNumber: invoiceNumber,
      orderId: json['order_id'] as String? ?? '',
      amountPaise: paise,
      amountRupees: paise / 100,
      currency: json['currency'] as String? ?? 'INR',
      keyId: json['key_id'] as String? ?? '',
    );
  }
}

/// Raised when the server declines an invoice-payment request, carrying the
/// message it gave so the UI can show something specific.
class InvoicePaymentException implements Exception {
  final String message;
  const InvoicePaymentException(this.message);
  @override
  String toString() => message;
}

/// Talks to the existing invoice-payment endpoints
/// (backend/controllers/payment_gateway_controller.go) — the same Razorpay
/// order-creation/signature-verification implementation subscription
/// checkout and consultation checkout already use, just pointed at an
/// invoice instead of a plan or a booking.
class InvoicePaymentRepository {
  /// Opens a gateway order for the invoice's remaining balance. The amount is
  /// decided server-side from the invoice itself (total - already paid) —
  /// the app never sends a price.
  Future<InvoiceCheckout> startCheckout({
    required String invoiceId,
    required String invoiceNumber,
  }) async {
    try {
      final res = await DioClient.instance
          .post('/payments/razorpay/order', data: {'invoice_id': invoiceId});
      final data = res.data['data'] as Map<String, dynamic>?;
      if (data == null || (data['order_id'] as String? ?? '').isEmpty) {
        throw const InvoicePaymentException(
            'Could not start payment. Please try again.');
      }
      return InvoiceCheckout.fromJson(invoiceNumber, data);
    } on DioException catch (e) {
      throw InvoicePaymentException(DioClient.describeError(e));
    }
  }

  /// Hands the gateway's signed result back for verification. The server
  /// recomputes the signature against its own secret and only then marks the
  /// invoice paid — nothing reported by the checkout page is trusted here.
  Future<void> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      await DioClient.instance.post('/payments/razorpay/verify', data: {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      });
    } on DioException catch (e) {
      throw InvoicePaymentException(DioClient.describeError(e));
    }
  }
}
