import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/auto_refresh_service.dart';

class ClientProvider extends ChangeNotifier {
  List<dynamic> _clients = [];
  bool _loading = false;
  String? _error;

  List<dynamic> get clients => _clients;
  bool get loading => _loading;
  String? get error => _error;

  ClientProvider() {
    AutoRefreshService.instance
        .register('clients', () => loadClients(silent: true));
  }

  @override
  void dispose() {
    AutoRefreshService.instance.unregister('clients');
    super.dispose();
  }

  // [silent] skips the loading-spinner flip — used by the global 3-second
  // auto-refresh (see AutoRefreshService) so a background poll updates the
  // list in place instead of blanking the screen back to a spinner.
  Future<void> loadClients({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      notifyListeners();
    }
    try {
      final res = await DioClient.instance.get('/clients');
      _clients = res.data['data'] ?? [];
      _error = null;
    } catch (e) {
      if (!silent) _error = e.toString();
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
