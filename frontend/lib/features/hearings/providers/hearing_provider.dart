import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';

class HearingProvider extends ChangeNotifier {
  List<dynamic> _hearings = [];
  bool _loading = false;

  List<dynamic> get hearings => _hearings;
  bool get loading => _loading;

  Future<void> loadHearings() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await DioClient.instance.get('/hearings');
      _hearings = res.data['data'] ?? [];
    } catch (e) {
      debugPrint('Hearings error: $e');
    }
    _loading = false;
    notifyListeners();
  }
}
