import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';

class ClientProvider extends ChangeNotifier {
  List<dynamic> _clients = [];
  bool _loading = false;
  String? _error;

  List<dynamic> get clients => _clients;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadClients() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await DioClient.instance.get('/clients');
      _clients = res.data['data'] ?? [];
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> addClient(Map<String, dynamic> data) async {
    try {
      await DioClient.instance.post('/clients', data: data);
      await loadClients();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ✅ New method - returns full response with portal credentials
  Future<Map<String, dynamic>?> addClientWithPortal(
      Map<String, dynamic> data) async {
    try {
      final res = await DioClient.instance.post('/clients', data: data);
      await loadClients();
      if (res.data['success'] == true) {
        return res.data['data'];
      }
      return null;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }
}
