import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';

class DashboardStats {
  final int totalClients;
  final int activeCases;
  final int pendingCases;
  final int wonCases;
  final int lostCases;
  final int todayHearings;
  final int upcomingHearings;
  final double totalRevenue;
  final double pendingBills;
  final int unreadMessages;

  DashboardStats({
    this.totalClients = 0,
    this.activeCases = 0,
    this.pendingCases = 0,
    this.wonCases = 0,
    this.lostCases = 0,
    this.todayHearings = 0,
    this.upcomingHearings = 0,
    this.totalRevenue = 0,
    this.pendingBills = 0,
    this.unreadMessages = 0,
  });
}

class DashboardProvider extends ChangeNotifier {
  DashboardStats _stats = DashboardStats();
  List<dynamic> _todayHearings = [];
  List<dynamic> _recentCases = [];
  List<dynamic> _recentActivities = [];
  bool _loading = false;

  DashboardStats get stats => _stats;
  List<dynamic> get todayHearings => _todayHearings;
  List<dynamic> get recentCases => _recentCases;
  List<dynamic> get recentActivities => _recentActivities;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// Loads the dashboard from the API's own `/dashboard` endpoint.
  ///
  /// This used to fan out into six parallel requests — /reports/cases,
  /// /reports/revenue, /hearings, /cases, /clients, /invoices — and assemble
  /// the numbers on the device. Three problems, all fixed here:
  ///
  ///  1. `.catchError((_) => null)` on a `Future<Response>` is a runtime type
  ///     error in Dart: the handler must return a Response, so the moment any
  ///     one of the six calls failed the whole load threw and the dashboard
  ///     rendered empty. The analyzer flagged all six lines.
  ///  2. It pulled every client and every invoice in the firm just to count
  ///     them and sum a balance — work the database does in one query, and a
  ///     payload that grows without limit as a firm takes on clients.
  ///  3. The backend already exposes `/dashboard`, which returns exactly this
  ///     shape in a single round trip.
  Future<void> loadDashboard() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await DioClient.instance.get('/dashboard');
      final data = response.data['data'] as Map<String, dynamic>? ?? {};
      final stats = data['stats'] as Map<String, dynamic>? ?? {};

      _stats = DashboardStats(
        totalClients: _asInt(stats['total_clients']),
        activeCases: _asInt(stats['active_cases']),
        pendingCases: _asInt(stats['pending_cases']),
        wonCases: _asInt(stats['won_cases']),
        lostCases: _asInt(stats['lost_cases']),
        todayHearings: _asInt(stats['today_hearings']),
        upcomingHearings: (data['upcoming_hearings'] as List?)?.length ?? 0,
        totalRevenue: _asDouble(stats['total_revenue']),
        pendingBills: _asDouble(stats['pending_amount']),
      );

      _todayHearings = (data['today_hearings'] as List?) ?? [];
      _recentCases = (data['recent_cases'] as List?) ?? [];
      _recentActivities = (data['recent_activities'] as List?) ?? [];
    } catch (e) {
      // Surfaced to the UI instead of only to the debug console, so a failed
      // load looks like a failure rather than an empty firm.
      _error = DioClient.describeError(e);
      debugPrint('Dashboard error: $e');
    }

    _loading = false;
    notifyListeners();
  }

  // JSON numbers arrive as int or double depending on whether the value has a
  // fractional part, so a bare `as int` cast throws on a whole-rupee total.
  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  static double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return 0;
  }
}
