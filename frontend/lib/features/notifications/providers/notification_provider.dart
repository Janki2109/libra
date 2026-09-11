import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/realtime_events.dart';

class NotificationProvider extends ChangeNotifier {
  List<dynamic> _notifications = [];
  bool _loading = false;

  List<dynamic> get notifications => _notifications;
  bool get loading => _loading;
  int get unreadCount =>
      _notifications.where((n) => !(n['is_read'] ?? false)).length;

  NotificationProvider() {
    // Every existing push (booking accepted/rejected, chat message,
    // session started, payment/billing updates, ...) already writes a real
    // notifications row on the backend (see utils.Notify/NotifyWithRef) —
    // this is what makes the bell badge/count update the instant one
    // arrives instead of only on the next manual open of the Notifications
    // screen.
    RealtimeEvents.instance.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent() => loadNotifications();

  @override
  void dispose() {
    RealtimeEvents.instance.removeListener(_onRealtimeEvent);
    super.dispose();
  }

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
