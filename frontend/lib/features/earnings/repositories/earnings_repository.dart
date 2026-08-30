import 'package:dio/dio.dart';

import '../../../core/services/dio_client.dart';

/// The lawyer's consultation-earnings summary — money received from clients
/// through the existing Razorpay consultation-booking flow. Distinct from
/// the firm's invoicing "Billing" (lib/features/billing/) and from the
/// lawyer's own SaaS subscription payments — this is what the LAWYER earns,
/// not what they owe or what they're billed.
class EarningsSummary {
  final double totalEarnings;
  final double totalReceived;
  final double pendingAmount;
  final double refundedAmount;
  final int completedPayments;
  final int pendingPayments;
  final int refundedPayments;
  final int totalTransactions;

  const EarningsSummary({
    required this.totalEarnings,
    required this.totalReceived,
    required this.pendingAmount,
    required this.refundedAmount,
    required this.completedPayments,
    required this.pendingPayments,
    required this.refundedPayments,
    required this.totalTransactions,
  });

  factory EarningsSummary.fromJson(Map<String, dynamic> json) => EarningsSummary(
        totalEarnings: (json['total_earnings'] as num?)?.toDouble() ?? 0,
        totalReceived: (json['total_received'] as num?)?.toDouble() ?? 0,
        pendingAmount: (json['pending_amount'] as num?)?.toDouble() ?? 0,
        refundedAmount: (json['refunded_amount'] as num?)?.toDouble() ?? 0,
        completedPayments: (json['completed_payments'] as num?)?.toInt() ?? 0,
        pendingPayments: (json['pending_payments'] as num?)?.toInt() ?? 0,
        refundedPayments: (json['refunded_payments'] as num?)?.toInt() ?? 0,
        totalTransactions: (json['total_transactions'] as num?)?.toInt() ?? 0,
      );

  static const empty = EarningsSummary(
    totalEarnings: 0,
    totalReceived: 0,
    pendingAmount: 0,
    refundedAmount: 0,
    completedPayments: 0,
    pendingPayments: 0,
    refundedPayments: 0,
    totalTransactions: 0,
  );
}

/// One row in the Billing transaction history.
class EarningsTransaction {
  final String id;
  final String clientName;
  final String consultationType;
  final String consultationDate;
  final String consultationTime;
  final String paymentStatus; // pending | paid | failed | refunded
  final double amountRupees;
  final String razorpayPaymentId;
  final String razorpayOrderId;
  final String paymentMethod;
  final DateTime? paidAt;
  final DateTime createdAt;

  const EarningsTransaction({
    required this.id,
    required this.clientName,
    required this.consultationType,
    required this.consultationDate,
    required this.consultationTime,
    required this.paymentStatus,
    required this.amountRupees,
    required this.razorpayPaymentId,
    required this.razorpayOrderId,
    required this.paymentMethod,
    required this.paidAt,
    required this.createdAt,
  });

  factory EarningsTransaction.fromJson(Map<String, dynamic> json) => EarningsTransaction(
        id: json['id'] as String? ?? '',
        clientName: (json['client_name'] as String?)?.trim().isNotEmpty == true
            ? json['client_name'] as String
            : 'Client',
        consultationType: json['consultation_type'] as String? ?? '',
        consultationDate: json['consultation_date'] as String? ?? '',
        consultationTime: json['consultation_time'] as String? ?? '',
        paymentStatus: json['payment_status'] as String? ?? 'pending',
        amountRupees: ((json['amount_paise'] as num?)?.toDouble() ?? 0) / 100,
        razorpayPaymentId: json['razorpay_payment_id'] as String? ?? '',
        razorpayOrderId: json['razorpay_order_id'] as String? ?? '',
        paymentMethod: json['payment_method'] as String? ?? '',
        paidAt: json['paid_at'] != null ? DateTime.tryParse(json['paid_at'] as String) : null,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class EarningsException implements Exception {
  final String message;
  const EarningsException(this.message);
  @override
  String toString() => message;
}

class EarningsResult {
  final EarningsSummary summary;
  final List<EarningsTransaction> transactions;
  final bool hasMore;
  const EarningsResult(this.summary, this.transactions, this.hasMore);
}

class EarningsRepository {
  /// [status] is 'all' | 'paid' | 'pending' | 'refunded'.
  /// [from]/[to] are 'YYYY-MM-DD', both optional.
  Future<EarningsResult> fetch({
    String status = 'all',
    String? from,
    String? to,
    int page = 1,
  }) async {
    try {
      final res = await DioClient.instance.get('/consultations/earnings', queryParameters: {
        'status': status,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
        'limit': 25,
      });
      final data = res.data['data'] as Map<String, dynamic>? ?? const {};
      final summary = EarningsSummary.fromJson(
          (data['summary'] as Map<String, dynamic>?) ?? const {});
      final txns = ((data['transactions'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EarningsTransaction.fromJson)
          .toList();
      final meta = res.data['meta'] as Map<String, dynamic>?;
      final hasMore = meta?['has_more'] as bool? ?? false;
      return EarningsResult(summary, txns, hasMore);
    } on DioException catch (e) {
      throw EarningsException(DioClient.describeError(e));
    }
  }
}
