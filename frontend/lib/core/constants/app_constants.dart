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
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://libra-caox.onrender.com/api/v1',
  );

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
