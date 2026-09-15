import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/auto_refresh_service.dart';

class CaseProvider extends ChangeNotifier {
  List<dynamic> _cases = [];
  bool _loading = false;
  String? _error;

  List<dynamic> get cases => _cases;
  bool get loading => _loading;
  String? get error => _error;

  CaseProvider() {
    AutoRefreshService.instance
        .register('cases', () => loadCases(silent: true));
  }

  @override
  void dispose() {
    AutoRefreshService.instance.unregister('cases');
    super.dispose();
  }

  // [silent]: see ClientProvider.loadClients — used by the global 3-second
  // auto-refresh so a background poll never re-shows the loading spinner.
  Future<void> loadCases({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      notifyListeners();
    }
    try {
      final res = await DioClient.instance.get('/cases');
      _cases = res.data['data'] ?? [];
      _error = null;
    } catch (e) {
      if (!silent) _error = DioClient.describeError(e);
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
      _error = DioClient.describeError(e);
      notifyListeners();
      return false;
    }
  }
}
