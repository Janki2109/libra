import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/auto_refresh_service.dart';

class HearingProvider extends ChangeNotifier {
  List<dynamic> _hearings = [];
  bool _loading = false;

  List<dynamic> get hearings => _hearings;
  bool get loading => _loading;

  HearingProvider() {
    AutoRefreshService.instance
        .register('hearings', () => loadHearings(silent: true));
  }

  @override
  void dispose() {
    AutoRefreshService.instance.unregister('hearings');
    super.dispose();
  }

  // [silent]: see ClientProvider.loadClients — used by the global 3-second
  // auto-refresh so a background poll never re-shows the loading spinner.
  Future<void> loadHearings({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      notifyListeners();
    }
    try {
      final res = await DioClient.instance.get('/hearings');
      _hearings = res.data['data'] ?? [];
    } catch (e) {
      debugPrint('Hearings error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  /// Called on logout/session-expiry (see main.dart) — this provider is a
  /// singleton that outlives any one login, so without this the previous
  /// account's hearings list would still render for the instant between
  /// logout and the next account's first load completing.
  void reset() {
    _hearings = [];
    _loading = false;
    notifyListeners();
  }
}
