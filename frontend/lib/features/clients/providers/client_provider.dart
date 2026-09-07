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

  Future<Map<String, dynamic>?> addClient(Map<String, dynamic> data) async {
    try {
      final res = await DioClient.instance.post('/clients', data: data);
      await loadClients();
      if (res.data['success'] == true) {
        return res.data['data'];
      }
      _error = res.data['message'] as String? ?? 'Failed to add client';
      notifyListeners();
      return null;
    } catch (e) {
      _error = DioClient.describeError(e);
      notifyListeners();
      return null;
    }
  }
}
