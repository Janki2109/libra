import 'package:flutter/foundation.dart';

class AppConstants {
  // ─── API ─────────────────────────────────
  //
  // Supplied at build time so one source tree produces dev, staging and
  // production builds:
  //
  //   flutter run   --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
  //   flutter build apk --release \
  //     --dart-define=API_BASE_URL=https://api.libralaw.in/api/v1
  //
  // This used to be a hardcoded constant with four commented-out alternatives
  // above it, so switching environments meant editing and rebuilding — and the
  // production URL was whichever line happened to be uncommented at the time.
  //
  // When no --dart-define is passed at all, a DEBUG run used to silently
  // fall back to the production Render URL — so "flutter run" with no flags
  // talked to production, not the local backend, and every "localhost isn't
  // working" report was actually "the local backend was never being talked
  // to in the first place." A release build with nothing passed still falls
  // back to production exactly as before (kReleaseMode below), which is what
  // keeps Render/production builds working unchanged; only an un-overridden
  // *debug* run now defaults to a platform-correct local address instead:
  //   - Chrome/web            -> localhost (the browser's own host)
  //   - Android emulator      -> 10.0.2.2 (the emulator's alias for the host)
  //   - iOS simulator/desktop -> localhost
  // A physical device on the LAN has no auto-detectable host address (the
  // dev machine's IP isn't knowable from the device), so that case still
  // requires passing --dart-define=API_BASE_URL=http://<LAN-IP>:8080/api/v1
  // explicitly — never hardcoded here.
  static String get baseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    if (kReleaseMode) return _prodUrl;
    if (kIsWeb) return 'http://localhost:8080/api/v1';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080/api/v1';
    }
    return 'http://localhost:8080/api/v1';
  }

  // This was 'https://libra-caox.onrender.com/api/v1' — a hostname with no
  // live service behind it (every request to it times out at the TCP/TLS
  // layer with no response at all, which is why login/registration spun
  // forever in a release build). Render's own deploy logs show the actual
  // live service at 'https://libra-y678.onrender.com' ("Available at your
  // primary URL" / "Your service is live"); verified directly — /health
  // returns 200 and /api/v1/auth/login returns a real 401 for bad
  // credentials. Render assigns this `<name>-<random-suffix>.onrender.com`
  // hostname itself and it changes if the service is ever renamed or
  // recreated, so if this goes stale again, Render's dashboard (Settings ->
  // the service's own page header) or these same deploy logs are the source
  // of truth — never guess or hardcode a new one without confirming it
  // responds first.
  static const String _prodUrl = 'https://libra-y678.onrender.com/api/v1';

  /// Whether the app is talking to a plaintext endpoint. Used to warn during
  /// development and to fail loudly in a release build.
  static bool get isInsecureEndpoint => baseUrl.startsWith('http://');

  // ─── WebRTC TURN (optional) ──────────────
  //
  // STUN alone (see webrtc_call_service.dart) fails to connect a call
  // whenever either side is behind a symmetric or carrier-grade NAT — very
  // common on Indian mobile data networks. A TURN server is what makes those
  // calls connect anyway (relaying media when a direct peer-to-peer path
  // can't be found), at the cost of running through a third party.
  // Username/credential are supplied at build time, same as API_BASE_URL, so
  // building without them configured degrades to STUN-only rather than
  // breaking the build:
  //
  //   flutter build apk --release \
  //     --dart-define=API_BASE_URL=https://libra-law.onrender.com/api/v1 \
  //     --dart-define=TURN_USERNAME=... \
  //     --dart-define=TURN_CREDENTIAL=...
  //
  // The relay hostnames themselves (global.relay.metered.ca) are Metered's
  // stable public TURN endpoint, not account-specific, so they're safe to
  // hardcode rather than thread through another dart-define each.
  static const String turnUsername = String.fromEnvironment('TURN_USERNAME');
  static const String turnCredential =
      String.fromEnvironment('TURN_CREDENTIAL');
  static bool get hasTurnServer => turnUsername.isNotEmpty;

  // ─── Storage Keys ────────────────────────
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';
  static const String themeKey = 'theme_mode';
  static const String onboardingSeenKey = 'onboarding_seen';

  // ─── App Info ────────────────────────────
  static const String appName = 'Libra Law Practice';
  static const String appTagline = 'Smart Legal Practice Management';
  static const String appVersion = '1.0.0';

  // ─── Timeouts ────────────────────────────
  // connectTimeout was 30s, which is cutting it close on a free-tier host
  // that can take 30-60s to wake from an idle spin-down before it even
  // accepts the TCP connection — a cold start could time out before the
  // server had a chance to respond at all.
  static const int connectTimeout = 60000;
  static const int receiveTimeout = 60000;
  static const int sendTimeout = 60000;

  // ─── Pagination ──────────────────────────
  static const int pageSize = 20;
}
