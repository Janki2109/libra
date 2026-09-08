import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../router/app_router.dart';
import 'dio_client.dart';

/// Handles a push that arrives while the app is backgrounded/terminated.
/// Must be a top-level (or static) function — it runs in its own isolate,
/// which is why it re-initializes Firebase itself. It intentionally does very
/// little: with a `notification` payload, Android/iOS already show the system
/// tray notification on their own; this only runs for silent/data-only
/// messages, and there are none of those in this app today.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// One FCM integration shared by every role (lawyer/client/student/admin) —
/// there is nothing role-specific here. AuthProvider calls [syncToken] after
/// any successful login/register and [clearToken] on logout; main.dart calls
/// [initialize] once at startup.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final _localNotifications = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel(
    'default_channel',
    'Notifications',
    description: 'Case, billing, verification and account notifications',
    importance: Importance.high,
  );

  bool _initialized = false;
  String? _lastToken;

  /// True once FirebaseMessaging.requestPermission() comes back denied —
  /// checked by the incoming-call flow so it can fail visibly (e.g. show a
  /// "you won't be notified of calls" banner) instead of silently never
  /// ringing.
  bool notificationsDenied = false;

  /// Fires with a consultation id whenever the *other* party cancels a call
  /// before it was answered (see CancelConsultationCall on the backend).
  /// IncomingCallScreen listens for its own consultationId here so it can
  /// stop ringing and dismiss itself even though it has no WebRTC socket
  /// open yet at that point.
  final ValueNotifier<String?> callCancelled = ValueNotifier(null);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[fcm] Firebase.initializeApp failed: $e');
      return; // no google-services.json / not configured for this platform
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (_) => _openNotifications(),
    );
    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    notificationsDenied =
        settings.authorizationStatus == AuthorizationStatus.denied;
    if (notificationsDenied) {
      // Not fatal — the rest of the app still works — but incoming-call
      // pushes specifically depend on this, so it's worth a clear log rather
      // than a call silently never ringing with no explanation.
      debugPrint('[fcm] notification permission denied — incoming call '
          'alerts will not be delivered on this device');
    }

    // Foreground: FCM does not show a system tray notification by itself, so
    // this shows one via flutter_local_notifications, matching what the user
    // sees when the app is backgrounded. An incoming-call push instead opens
    // the incoming-call screen directly — the app is already in front, so
    // there's no reason to make the client tap a tray notification first.
    FirebaseMessaging.onMessage.listen((message) {
      if (_openIncomingCallIfAny(message.data)) return;
      if (_handleCallCancelledIfAny(message.data)) return;
      final n = message.notification;
      if (n == null) return;
      _localNotifications.show(
        n.hashCode,
        n.title,
        n.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            'Notifications',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    });

    // Tapped a notification while the app was backgrounded, or launched the
    // app cold from a notification tap.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (!_openIncomingCallIfAny(message.data)) _openNotifications();
    });
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      // main() awaits this whole initialize() call *before* runApp(), so
      // AppRouter.current is still null right here — pushing now would
      // silently no-op and the tap that cold-started the app (e.g. an
      // incoming call) would go nowhere. Wait for the router to exist first.
      AppRouter.ready.then((_) {
        if (!_openIncomingCallIfAny(initialMessage.data)) _openNotifications();
      });
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _lastToken = token;
      _registerToken(token);
    });
  }

  void _openNotifications() {
    AppRouter.current?.push('/notifications');
  }

  /// If this push carries the incoming-call data InitiateConsultationCall
  /// sends (see backend/controllers/consultation_controller.go), opens the
  /// incoming-call screen and returns true; otherwise leaves the message for
  /// the normal notification handling and returns false.
  bool _openIncomingCallIfAny(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    if (!type.startsWith('incoming_call_')) return false;
    final callType = type.substring('incoming_call_'.length); // 'audio' | 'video'
    final consultationId = data['reference_id'] as String? ?? '';
    if (consultationId.isEmpty) return false;
    final body = data['body'] as String? ?? '';
    final lawyerName = body.replaceAll(RegExp(r'\s*is calling you\.?$'), '');
    AppRouter.current?.push('/incoming-call', extra: {
      'consultationId': consultationId,
      'callType': callType,
      'lawyerName': lawyerName.isNotEmpty ? lawyerName : 'Your Lawyer',
    });
    return true;
  }

  /// If this push is CancelConsultationCall's "the caller hung up before you
  /// answered" notice, tells any open IncomingCallScreen for that
  /// consultation to stop ringing and dismiss, and returns true so normal
  /// notification handling doesn't also show a tray notification for it.
  bool _handleCallCancelledIfAny(Map<String, dynamic> data) {
    if (data['type'] != 'call_cancelled') return false;
    final consultationId = data['reference_id'] as String? ?? '';
    if (consultationId.isEmpty) return false;
    callCancelled.value = consultationId;
    // Reset immediately after so a second cancel on the same id (unlikely,
    // but a stale value should never re-trigger it) still notifies listeners
    // via a fresh assignment.
    Future.microtask(() => callCancelled.value = null);
    return true;
  }

  /// Shows an immediate local notification using the same plugin/channel
  /// already initialized for FCM pushes above. Used for events that only the
  /// device itself knows about right when they happen (e.g. a lawyer
  /// confirming a consultation) — no server-side notification row is
  /// involved, so callers must pass real data, never placeholder text.
  Future<void> showLocalNotification(String title, String body) async {
    if (!_initialized) return;
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            'Notifications',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('[fcm] local notification failed: $e');
    }
  }

  /// Call after any successful login/register, for every role — gets (or
  /// reuses) the device's FCM token and associates it with whichever user
  /// just signed in.
  Future<void> syncToken() async {
    if (!_initialized) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      _lastToken = token;
      await _registerToken(token);
    } catch (e) {
      debugPrint('[fcm] could not obtain token: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await DioClient.instance.post('/fcm/token', data: {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (e) {
      debugPrint('[fcm] token registration failed: $e');
    }
  }

  /// Call on logout so a signed-out device stops receiving that user's
  /// pushes. Must run before the auth token/header is cleared.
  Future<void> clearToken() async {
    final token = _lastToken;
    if (token == null) return;
    try {
      await DioClient.instance.delete('/fcm/token', data: {'token': token});
    } catch (e) {
      debugPrint('[fcm] token cleanup failed: $e');
    }
  }
}
