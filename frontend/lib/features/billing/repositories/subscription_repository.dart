import 'package:dio/dio.dart';

import '../../../core/services/dio_client.dart';

/// A plan as the server defines it.
///
/// The paywall screen used to hold its own hardcoded list — four plans at
/// ₹99/₹499/₹999/₹2999 that existed nowhere in the database. Changing a price
/// meant shipping an app update, and the price shown never had to agree with
/// the price charged. The plans table is the single source of truth now.
class Plan {
  final String id;
  final String name; // 'solo', 'firm', ...
  final String displayName;
  final double priceMonthly;
  final double priceYearly;
  final int maxCases;
  final int maxStaff;
  final int maxClients;
  final List<String> features;

  const Plan({
    required this.id,
    required this.name,
    required this.displayName,
    required this.priceMonthly,
    required this.priceYearly,
    required this.maxCases,
    required this.maxStaff,
    required this.maxClients,
    required this.features,
  });

  bool get isFree => priceMonthly <= 0;

  /// Yearly billing as a percentage saved, or null when there is no discount.
  int? get yearlySavingPercent {
    if (priceMonthly <= 0 || priceYearly <= 0) return null;
    final fullYear = priceMonthly * 12;
    if (priceYearly >= fullYear) return null;
    return (((fullYear - priceYearly) / fullYear) * 100).round();
  }

  factory Plan.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['features'];
    return Plan(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      displayName: json['display_name'] as String? ?? json['name'] as String? ?? '',
      priceMonthly: _num(json['price_monthly']),
      priceYearly: _num(json['price_yearly']),
      maxCases: _int(json['max_cases']),
      maxStaff: _int(json['max_staff']),
      maxClients: _int(json['max_clients']),
      features: rawFeatures is String && rawFeatures.trim().isNotEmpty
          ? rawFeatures.split(',').map((f) => f.trim()).toList()
          : const [],
    );
  }

  static double _num(dynamic v) => v is num ? v.toDouble() : 0;
  static int _int(dynamic v) => v is num ? v.toInt() : 0;

  /// 0 means unlimited in the plans table.
  String limitLabel(int value, String noun) =>
      value == 0 ? 'Unlimited $noun' : '$value $noun';
}

/// A gateway order opened for a plan purchase.
class Checkout {
  final String orderId;
  final int amountPaise;
  final double amountRupees;
  final String currency;
  final String keyId;
  final String planName;
  final String billingCycle;

  const Checkout({
    required this.orderId,
    required this.amountPaise,
    required this.amountRupees,
    required this.currency,
    required this.keyId,
    required this.planName,
    required this.billingCycle,
  });

  factory Checkout.fromJson(Map<String, dynamic> json) => Checkout(
        orderId: json['order_id'] as String? ?? '',
        amountPaise: (json['amount'] as num?)?.toInt() ?? 0,
        amountRupees: (json['amount_rupees'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'INR',
        keyId: json['key_id'] as String? ?? '',
        planName: json['plan_name'] as String? ?? '',
        billingCycle: json['billing_cycle'] as String? ?? 'monthly',
      );
}

/// Raised when the server declines a billing request, carrying the message it
/// gave so the UI can show something specific rather than "an error occurred".
class BillingException implements Exception {
  final String message;
  const BillingException(this.message);
  @override
  String toString() => message;
}

class SubscriptionRepository {
  /// Plans available to buy, cheapest first, free tiers omitted.
  Future<List<Plan>> fetchPlans() async {
    try {
      final res = await DioClient.instance.get('/auth/plans');
      final data = res.data['data'] as List? ?? const [];
      final plans = data
          .whereType<Map<String, dynamic>>()
          .map(Plan.fromJson)
          .where((p) => !p.isFree)
          .toList()
        ..sort((a, b) => a.priceMonthly.compareTo(b.priceMonthly));
      return plans;
    } on DioException catch (e) {
      throw BillingException(DioClient.describeError(e));
    }
  }

  /// Opens a gateway order. The amount is decided by the server from the plans
  /// table — the app never sends a price.
  Future<Checkout> startCheckout({
    required String plan,
    required String billingCycle,
  }) async {
    try {
      final res = await DioClient.instance.post('/subscription/checkout', data: {
        'plan': plan,
        'billing_cycle': billingCycle,
      });
      final data = res.data['data'] as Map<String, dynamic>?;
      if (data == null || (data['order_id'] as String? ?? '').isEmpty) {
        throw const BillingException('Could not start checkout. Please try again.');
      }
      return Checkout.fromJson(data);
    } on DioException catch (e) {
      throw BillingException(DioClient.describeError(e));
    }
  }

  /// Hands the gateway's signed result back for verification.
  ///
  /// This is the fast path only. The server also receives a webhook straight
  /// from the gateway and treats that as authoritative, so a payment still
  /// activates even if the user kills the app on this screen.
  Future<void> activate({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      await DioClient.instance.post('/subscription/activate', data: {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      });
    } on DioException catch (e) {
      throw BillingException(DioClient.describeError(e));
    }
  }

  Future<void> cancel() async {
    try {
      await DioClient.instance.post('/subscription/cancel');
    } on DioException catch (e) {
      throw BillingException(DioClient.describeError(e));
    }
  }

  /// Past subscription charges, for the billing history screen.
  Future<List<Map<String, dynamic>>> fetchPaymentHistory() async {
    try {
      final res = await DioClient.instance.get('/subscription/payments');
      final data = res.data['data'] as List? ?? const [];
      return data.whereType<Map<String, dynamic>>().toList();
    } on DioException catch (e) {
      throw BillingException(DioClient.describeError(e));
    }
  }
}
