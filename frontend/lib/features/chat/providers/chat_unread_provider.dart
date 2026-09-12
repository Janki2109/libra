import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/realtime_events.dart';

/// Real unread-message count for the Home screen's chat badge, backed by
/// the existing GET /chat/unread endpoint (chat_messages.is_read, already
/// flipped to true whenever a room's messages are opened via GetMessages).
/// Mirrors NotificationProvider's pattern exactly, just for the separate
/// chat badge — the two were wrongly sharing one counter before this.
class ChatUnreadProvider extends ChangeNotifier {
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  ChatUnreadProvider() {
    // A new chat_message push (see notifyOtherChatParticipants on the
    // backend) or opening a room to read it both mean this count may be
    // stale — refresh on the same realtime event bus the rest of the app
    // already uses instead of a timer or manual refresh.
    RealtimeEvents.instance.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent() {
    if (RealtimeEvents.instance.matches(['chat_message'])) load();
  }

  @override
  void dispose() {
    RealtimeEvents.instance.removeListener(_onRealtimeEvent);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final res = await DioClient.instance.get('/chat/unread');
      _unreadCount = (res.data['data']?['count'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } catch (e) {
      debugPrint('Chat unread count error: $e');
    }
  }
}
