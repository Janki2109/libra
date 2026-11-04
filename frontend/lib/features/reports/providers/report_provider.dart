import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';

class ReportProvider extends ChangeNotifier {
  Map<String, dynamic> _caseReport = {};
  Map<String, dynamic> _revenueReport = {};
  bool _loading = false;

  Map<String, dynamic> get caseReport => _caseReport;
  Map<String, dynamic> get revenueReport => _revenueReport;
  bool get loading => _loading;

  Future<void> loadReports() async {
    _loading = true;
    notifyListeners();
    try {
      final caseRes = await DioClient.instance.get('/reports/cases');
      final revRes = await DioClient.instance.get('/reports/revenue');
      _caseReport = caseRes.data['data'] ?? {};
      _revenueReport = revRes.data['data'] ?? {};
    } catch (e) {
      debugPrint('Reports error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  /// Called on logout/session-expiry (see main.dart) — this provider is a
  /// singleton that outlives any one login, so without this the previous
  /// account's report data would still render for the instant between
  /// logout and the next account's first load completing.
  void reset() {
    _caseReport = {};
    _revenueReport = {};
    _loading = false;
    notifyListeners();
  }
}
