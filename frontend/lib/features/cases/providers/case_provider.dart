import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';

class CaseProvider extends ChangeNotifier {
  List<dynamic> _cases = [];
  bool _loading = false;
  String? _error;

  List<dynamic> get cases => _cases;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadCases() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await DioClient.instance.get('/cases');
      _cases = res.data['data'] ?? [];
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> addCase(Map<String, dynamic> data) async {
    try {
      await DioClient.instance.post('/cases', data: data);
      await loadCases();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }
}
