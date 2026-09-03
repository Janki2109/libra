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
    defaultValue: 'http://localhost:8080/api/v1',
  );

  /// Whether the app is talking to a plaintext endpoint. Used to warn during
  /// development and to fail loudly in a release build.
  static bool get isInsecureEndpoint => baseUrl.startsWith('http://');

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
  static const int connectTimeout = 30000;
  static const int receiveTimeout = 60000;
  static const int sendTimeout = 60000;

  // ─── Pagination ──────────────────────────
  static const int pageSize = 20;
}
