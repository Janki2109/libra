import 'package:flutter/foundation.dart';

/// The app's realtime transport is the existing FCM pipeline (see
/// FcmService) — the backend already pushes a typed notification for every
/// booking/chat/call/payment event that matters (see utils.NotifyWithRef on
/// the Go side). What was missing was anything on the Flutter side turning
/// "a push arrived" into "the screen showing that data refreshes itself" —
/// screens only ever reloaded on their own initState or a manual
/// pull-to-refresh, so a lawyer sitting on My Bookings never saw a new
/// request appear until they backed out and back in.
///
/// This is a tiny broadcast point, not a new realtime protocol: FcmService
/// calls [emit] with the push's own `data['type']` every time one arrives
/// (foreground or tapped-from-background), and any currently-open screen
/// that cares listens and re-runs its own existing load method — never a
/// timer, never a full-app reload, just "this one thing might be stale, ask
/// the backend again."
class RealtimeEvents extends ChangeNotifier {
  RealtimeEvents._();
  static final RealtimeEvents instance = RealtimeEvents._();

  /// The most recent event's notification `type` (e.g. "booking_accepted",
  /// "booking_rejected", "booking_request", "chat_message",
  /// "incoming_call_audio", "session_started_chat", "booking_expired").
  String? lastType;

  /// Bumped on every emit so a listener can tell two same-typed events
  /// apart (e.g. two different chat messages) even though [lastType]
  /// didn't change.
  int version = 0;

  void emit(String? type) {
    if (type == null || type.isEmpty) return;
    lastType = type;
    version++;
    notifyListeners();
  }

  /// True if the most recent event's type starts with any of [prefixes] —
  /// screens use this instead of an exact match since related events share
  /// a prefix (e.g. "booking_accepted"/"booking_rejected"/"booking_request").
  bool matches(List<String> prefixes) {
    final t = lastType;
    if (t == null) return false;
    return prefixes.any((p) => t.startsWith(p));
  }
}
