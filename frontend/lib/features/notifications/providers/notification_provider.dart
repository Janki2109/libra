import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';

class NotificationProvider extends ChangeNotifier {
  List<dynamic> _notifications = [];
  bool _loading = false;

  List<dynamic> get notifications => _notifications;
  bool get loading => _loading;
  int get unreadCount =>
      _notifications.where((n) => !(n['is_read'] ?? false)).length;

  Future<void> loadNotifications() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await DioClient.instance.get('/notifications');
      _notifications = res.data['data'] ?? [];
    } catch (e) {
      debugPrint('Notifications error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> markAsRead(String id) async {
    try {
      await DioClient.instance.put('/notifications/$id/read');
      final index = _notifications.indexWhere((n) => n['id'] == id);
      if (index != -1) {
        _notifications[index]['is_read'] = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Mark read error: $e');
    }
  }
}
