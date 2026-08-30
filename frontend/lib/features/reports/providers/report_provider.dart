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
}
