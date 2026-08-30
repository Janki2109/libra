import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';

class StaffProvider extends ChangeNotifier {
  List<dynamic> _staff = [];
  bool _loading = false;
  String? _error;

  List<dynamic> get staff => _staff;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadStaff() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await DioClient.instance.get('/staff');
      _staff = res.data['data'] ?? [];
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> addStaff(Map<String, dynamic> data) async {
    _error = null;
    try {
      await DioClient.instance.post('/staff', data: data);
      await loadStaff();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateStaff(String id, Map<String, dynamic> data) async {
    try {
      await DioClient.instance.put('/staff/$id', data: data);
      await loadStaff();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }
}
