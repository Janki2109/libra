import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dio_client.dart';

/// Entitlement state for the current account.
class SubscriptionStatus {
  final String status; // trial | active | trial_expired | expired | cancelled | none
  final bool isActive;
  final bool requiresPlan;
  final int daysRemaining;
  final String planName;

  const SubscriptionStatus({
    required this.status,
    required this.isActive,
    required this.requiresPlan,
    required this.daysRemaining,
    required this.planName,
  });

  bool get isTrial => status == 'trial';

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      status: json['status'] as String? ?? 'none',
      isActive: json['is_active'] as bool? ?? false,
      requiresPlan: json['requires_plan'] as bool? ?? true,
      daysRemaining: (json['days_remaining'] as num?)?.toInt() ?? 0,
      planName: json['plan_name'] as String? ?? '',
    );
  }

  /// Used when the app cannot reach the server. Access is allowed so a lawyer
  /// on a bad connection is not locked out of their own case files, but
  /// nothing is treated as newly purchased.
  static const unknown = SubscriptionStatus(
    status: 'unknown',
    isActive: true,
    requiresPlan: false,
    daysRemaining: 0,
    planName: '',
  );
}

/// Reads the account's entitlement from the API.
///
/// This used to be entirely local: a `first_launch_date` string and an
/// `is_subscribed` boolean in SharedPreferences, with `setSubscribed(true)`
/// callable from the client. Clearing app data reset the trial, reinstalling
/// reset the trial, and editing the plaintext prefs file granted a permanent
/// subscription — so the paywall could not actually collect money. The server
/// owns this now (GET /api/v1/subscription); the local copy is only a cache so
/// the app has something to show before the first response arrives.
class TrialService {
  static const _cacheStatus = 'sub_status_cache';
  static const _cacheDays = 'sub_days_cache';
  static const _cacheActive = 'sub_active_cache';

  static SubscriptionStatus? _current;

  /// The last known status, refreshing from the server in the background.
  static SubscriptionStatus? get current => _current;

  /// Fetches the authoritative status. Falls back to the cached value, then to
  /// [SubscriptionStatus.unknown], if the server cannot be reached.
  static Future<SubscriptionStatus> refresh() async {
    try {
      final response = await DioClient.instance.get('/subscription');
      final data = response.data['data'];
      if (data is Map<String, dynamic>) {
        final status = SubscriptionStatus.fromJson(data);
        _current = status;
        await _cache(status);
        return status;
      }
    } on DioException {
      // Offline or the server is down — fall through to the cache.
    }

    final cached = await _readCache();
    _current = cached;
    return cached;
  }

  /// True when the account may use paid features.
  static Future<bool> isActive() async {
    final status = _current ?? await refresh();
    return status.isActive;
  }

  static Future<int> daysRemaining() async {
    final status = _current ?? await refresh();
    return status.daysRemaining;
  }

  /// Clears the cached entitlement. Call on logout.
  static Future<void> clear() async {
    _current = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheStatus);
    await prefs.remove(_cacheDays);
    await prefs.remove(_cacheActive);
  }

  static Future<void> _cache(SubscriptionStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheStatus, status.status);
    await prefs.setInt(_cacheDays, status.daysRemaining);
    await prefs.setBool(_cacheActive, status.isActive);
  }

  static Future<SubscriptionStatus> _readCache() async {
    final prefs = await SharedPreferences.getInstance();
    final status = prefs.getString(_cacheStatus);
    if (status == null) return SubscriptionStatus.unknown;

    return SubscriptionStatus(
      status: status,
      isActive: prefs.getBool(_cacheActive) ?? true,
      requiresPlan: !(prefs.getBool(_cacheActive) ?? true),
      daysRemaining: prefs.getInt(_cacheDays) ?? 0,
      planName: '',
    );
  }
}
