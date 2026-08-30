import 'package:dio/dio.dart';

import '../../../core/services/dio_client.dart';

/// A Razorpay order opened for a single consultation booking.
///
/// Mirrors billing/repositories/subscription_repository.dart's `Checkout` —
/// same shape, same "server decides the amount" rule — but for a one-time
/// consultation payment rather than a recurring plan, and it carries the
/// booking details the confirmation screen needs (lawyer, type, date, time).
class ConsultationCheckout {
  final String consultationId;
  final String orderId;
  final int amountPaise;
  final double amountRupees;
  final String currency;
  final String keyId;
  final String lawyerName;
  final String consultationType;
  final String consultationDate;
  final String consultationTime;

  const ConsultationCheckout({
    required this.consultationId,
    required this.orderId,
    required this.amountPaise,
    required this.amountRupees,
    required this.currency,
    required this.keyId,
    required this.lawyerName,
    required this.consultationType,
    required this.consultationDate,
    required this.consultationTime,
  });

  factory ConsultationCheckout.fromJson(Map<String, dynamic> json) =>
      ConsultationCheckout(
        consultationId: json['consultation_id'] as String? ?? '',
        orderId: json['order_id'] as String? ?? '',
        amountPaise: (json['amount'] as num?)?.toInt() ?? 0,
        amountRupees: (json['amount_rupees'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'INR',
        keyId: json['key_id'] as String? ?? '',
        lawyerName: json['lawyer_name'] as String? ?? '',
        consultationType: json['consultation_type'] as String? ?? '',
        consultationDate: json['consultation_date'] as String? ?? '',
        consultationTime: json['consultation_time'] as String? ?? '',
      );
}

/// Raised when the server declines a consultation-payment request, carrying
/// the message it gave so the UI can show something specific instead of a
/// raw exception.
class ConsultationPaymentException implements Exception {
  final String message;
  const ConsultationPaymentException(this.message);
  @override
  String toString() => message;
}

class ConsultationRepository {
  /// Opens a gateway order for a consultation booking. The amount is decided
  /// server-side (consultationPricePaise in the Go controller) — the app
  /// never sends a price.
  ///
  /// Pass [consultationId] to retry an existing unpaid booking (a cancelled
  /// or failed previous attempt) rather than creating a new one.
  Future<ConsultationCheckout> startCheckout({
    String? consultationId,
    required String lawyerId,
    required String consultationType,
    required String consultationDate,
    required String consultationTime,
    String notes = '',
  }) async {
    try {
      final res = await DioClient.instance.post('/portal/book-consultation/checkout', data: {
        if (consultationId != null) 'consultation_id': consultationId,
        'lawyer_id': lawyerId,
        'consultation_type': consultationType,
        'consultation_date': consultationDate,
        'consultation_time': consultationTime,
        'notes': notes,
      });
      final data = res.data['data'] as Map<String, dynamic>?;
      if (data == null || (data['order_id'] as String? ?? '').isEmpty) {
        throw const ConsultationPaymentException(
            'Could not start payment. Please try again.');
      }
      return ConsultationCheckout.fromJson(data);
    } on DioException catch (e) {
      throw ConsultationPaymentException(DioClient.describeError(e));
    }
  }

  /// Re-reads a booking's actual server-side state. Used after the web
  /// checkout fallback (a new browser tab with no way to hand a signature
  /// back to this app) to confirm payment_status really is 'paid' before the
  /// UI claims success — the tab closing or a button tap is never itself
  /// treated as proof of payment.
  Future<Map<String, dynamic>?> fetchConsultation(String consultationId) async {
    try {
      final res = await DioClient.instance.get('/portal/my-consultations/$consultationId');
      return res.data['data'] as Map<String, dynamic>?;
    } on DioException {
      return null;
    }
  }

  /// Hands the gateway's signed result back for server-side verification.
  /// The booking is confirmed only if this succeeds — the server recomputes
  /// the signature itself rather than trusting the app's word that payment
  /// succeeded.
  Future<Map<String, dynamic>> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      final res = await DioClient.instance.post('/portal/book-consultation/verify', data: {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      });
      return (res.data['data'] as Map<String, dynamic>?) ?? const {};
    } on DioException catch (e) {
      throw ConsultationPaymentException(DioClient.describeError(e));
    }
  }
}
