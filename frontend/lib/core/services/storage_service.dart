import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// Persists the session.
///
/// The auth token moved from SharedPreferences to flutter_secure_storage.
/// SharedPreferences is a plaintext XML file in the app sandbox on Android and
/// an unprotected plist on iOS — readable by anything with filesystem access on
/// a rooted or jailbroken device, and included in unencrypted device backups.
/// This app's token grants access to privileged client files, so it belongs in
/// the Keychain / EncryptedSharedPreferences instead. The dependency was
/// already in pubspec.yaml but nothing used it.
class StorageService {
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ─── TOKEN ───────────────────────────────
  static Future<void> saveToken(String token) async {
    await _secure.write(key: AppConstants.tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    final token = await _secure.read(key: AppConstants.tokenKey);
    if (token != null) return token;

    // One-time migration for users upgrading from a build that stored the
    // token in SharedPreferences: move it across, then delete the plaintext
    // copy so it does not linger on disk.
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(AppConstants.tokenKey);
    if (legacy != null && legacy.isNotEmpty) {
      await saveToken(legacy);
      await prefs.remove(AppConstants.tokenKey);
      return legacy;
    }
    return null;
  }

  static Future<void> clearToken() async {
    await _secure.delete(key: AppConstants.tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
  }

  // ─── USER PROFILE ────────────────────────
  // Name, email and role — not a credential, so plain preferences are fine
  // and keep startup fast.
  static Future<void> saveUser(String userJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.userKey, userJson);
  }

  static Future<String?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.userKey);
  }

  // ─── SESSION ─────────────────────────────
  static Future<void> clearAll() async {
    // prefs.clear() alone left the token behind once it moved to secure
    // storage, so "log out" did not actually end the session.
    await _secure.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString(AppConstants.themeKey);
    final onboardingSeen = prefs.getBool(AppConstants.onboardingSeenKey);
    await prefs.clear();
    // Logging out should not reset the user's theme choice or make
    // onboarding reappear — both are app-level, not session-level.
    if (theme != null) {
      await prefs.setString(AppConstants.themeKey, theme);
    }
    if (onboardingSeen != null) {
      await prefs.setBool(AppConstants.onboardingSeenKey, onboardingSeen);
    }
  }

  static Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ─── ONBOARDING ──────────────────────────
  // A one-time, app-level flag — not tied to a login session, so it survives
  // logout the same way the theme choice does.
  static Future<void> setOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.onboardingSeenKey, true);
  }

  static Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConstants.onboardingSeenKey) ?? false;
  }

}
