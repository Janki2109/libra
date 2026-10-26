import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/auto_refresh_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/trial_service.dart';
import '../models/auth_model.dart';

/// Turns an auth failure (login OR registration) into the right message for
/// the right cause, instead of a blanket "Login/Registration failed" for
/// every DioException — which made a release build pointed at an unreachable
/// API (e.g. still compiled with the default localhost base URL) look exactly
/// like a wrong password or a duplicate account, with nothing in the UI to
/// tell them apart.
///
/// Only a real response body with a server-written message (wrong
/// credentials, duplicate email, validation failure, 5xx) is shown as-is;
/// every network-level failure (no connection, DNS, timeout, TLS) gets its
/// own distinct, honest message instead via [DioClient.describeError].
String _describeAuthError(DioException e) {
  final data = e.response?.data;
  if (data is Map && data['message'] is String) {
    // The backend actually answered — this is a real rejection (bad
    // credentials, duplicate account, validation error), not connectivity.
    return data['message'] as String;
  }
  return DioClient.describeError(e);
}

/// Safe diagnostic logging for every auth request: endpoint, duration and
/// outcome category only. Never logs request/response bodies, so an email,
/// password, OTP or token can never end up here even by accident — unlike
/// request/response-body logging, which would.
void _logAuthRequest(String endpoint, Stopwatch stopwatch,
    {int? statusCode, Object? error}) {
  final ms = stopwatch.elapsedMilliseconds;
  if (error == null) {
    debugPrint('[auth] POST $endpoint -> ${AppConstants.baseUrl} '
        'ok status=$statusCode duration=${ms}ms');
    return;
  }
  if (error is DioException) {
    debugPrint('[auth] POST $endpoint -> ${AppConstants.baseUrl} failed: '
        'type=${error.type} status=${error.response?.statusCode} '
        'duration=${ms}ms');
  } else {
    debugPrint('[auth] POST $endpoint -> ${AppConstants.baseUrl} failed: '
        '${error.runtimeType} duration=${ms}ms');
  }
}

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  UserModel? _user;
  String? _token;
  bool _loading = false;
  String? _error;

  AuthStatus get status => _status;
  UserModel? get user => _user;
  String? get token => _token;
  bool get loading => _loading;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isAdmin => _user?.isAdmin ?? false;

  AuthProvider() {
    _checkSession();
  }

  Future<void> _checkSession() async {
    try {
      final token = await StorageService.getToken();
      final userJson = await StorageService.getUser();
      if (token != null && userJson != null && token.isNotEmpty) {
        _token = token;
        _user = UserModel.fromJson(jsonDecode(userJson));
        _status = AuthStatus.authenticated;
        FcmService.instance.syncToken();
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  // ─── LAWYER / STUDENT LOGIN ───────────────
  // [role] is which of this email's accounts to sign into ('lawyer' or
  // 'law_student') — the same email can now back a separate account per
  // role, so the backend needs this to know which one, not just the email.
  Future<bool> login(String email, String password, String role) async {
    _loading = true;
    _error = null;
    notifyListeners();
    final sw = Stopwatch()..start();
    try {
      final response = await DioClient.instance.post('/auth/login', data: {
        'email': email,
        'password': password,
        'role': role,
      });
      _logAuthRequest('/auth/login', sw,
          statusCode: response.statusCode);
      if (response.data['success'] == true) {
        final data = response.data['data'];
        _token = data['token']?.toString() ?? '';
        _user = UserModel.fromJson(data['user'] ?? {});
        await StorageService.saveToken(_token!);
        await StorageService.saveUser(jsonEncode(_user!.toJson()));
        _status = AuthStatus.authenticated;
        _loading = false;
        notifyListeners();
        FcmService.instance.syncToken();
        return true;
      } else {
        _error = response.data['message'] ?? 'Login failed';
      }
    } on DioException catch (e) {
      _logAuthRequest('/auth/login', sw, error: e);
      _error = _describeAuthError(e);
    } catch (e) {
      _logAuthRequest('/auth/login', sw, error: e);
      _error = 'Connection failed. Check internet & backend.';
    }
    _loading = false;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
    return false;
  }

  // ─── CLIENT LOGIN ─────────────────────────
  Future<bool> portalLogin(String email, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    final sw = Stopwatch()..start();
    try {
      final response = await DioClient.instance.post('/portal/login', data: {
        'email': email,
        'password': password,
      });
      _logAuthRequest('/portal/login', sw,
          statusCode: response.statusCode);
      if (response.data['success'] == true) {
        final data = response.data['data'];
        _token = data['token']?.toString() ?? '';
        _user = UserModel.fromJson(data['user'] ?? {});
        await StorageService.saveToken(_token!);
        await StorageService.saveUser(jsonEncode(_user!.toJson()));
        _status = AuthStatus.authenticated;
        _loading = false;
        notifyListeners();
        FcmService.instance.syncToken();
        return true;
      } else {
        _error = response.data['message'] ?? 'Login failed';
      }
    } on DioException catch (e) {
      _logAuthRequest('/portal/login', sw, error: e);
      _error = _describeAuthError(e);
    } catch (e) {
      _logAuthRequest('/portal/login', sw, error: e);
      _error = 'Connection failed. Check internet & backend.';
    }
    _loading = false;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
    return false;
  }

  // ─── REGISTER ────────────────────────────
  Future<bool> register({
    required String firmName,
    required String name,
    required String email,
    required String phone,
    required String password,
    String barCouncilNumber = '',
    String city = '',
    String state = '',
    String plan = '',
    String designation = '',
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    final sw = Stopwatch()..start();
    try {
      final response = await DioClient.instance.post('/auth/register', data: {
        'firm_name': firmName,
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'bar_council_number': barCouncilNumber,
        'city': city,
        'state': state,
        'plan': plan,
        'designation': designation,
      });
      _logAuthRequest('/auth/register', sw, statusCode: response.statusCode);

      if (response.data['success'] == true) {
        final data = response.data['data'];
        _token = data['token']?.toString() ?? '';
        _user = UserModel(
          id: data['user_id']?.toString() ?? '',
          name: name,
          email: email,
          phone: phone,
          // Matches the backend: a firm's founding user is role='lawyer',
          // same as anyone added afterwards — there is no separate "admin"
          // role in the system.
          roleName: 'lawyer',
          firmId: data['firm_id']?.toString() ?? '',
          // The register response itself never echoes designation back —
          // it's stored server-side correctly, but this model is built
          // straight from the request without it, so a lawyer's own
          // designation showed "Not set" from the moment they signed up
          // until something else (e.g. Edit Profile) happened to refetch it.
          designation: designation,
        );
        if (_token!.isNotEmpty) {
          await StorageService.saveToken(_token!);
        }
        await StorageService.saveUser(jsonEncode(_user!.toJson()));
        _status = AuthStatus.authenticated;
        _loading = false;
        notifyListeners();
        FcmService.instance.syncToken();
        return true;
      } else {
        _error = response.data['message'] ?? 'Registration failed';
      }
    } on DioException catch (e) {
      _logAuthRequest('/auth/register', sw, error: e);
      _error = _describeAuthError(e);
    } catch (e) {
      _logAuthRequest('/auth/register', sw, error: e);
      _error = 'Connection failed. Check internet & backend.';
    }
    _loading = false;
    notifyListeners();
    return false;
  }

  // ─── LAWYER VERIFICATION DOCUMENT (post-registration) ───
  // Reuses the existing /documents/upload endpoint with no case/client
  // attached, so no backend changes are needed for this.
  Future<bool> uploadVerificationDocument({
    required String fileName,
    required String mimeType,
    required String base64Content,
  }) async {
    try {
      final response =
          await DioClient.instance.post('/documents/upload', data: {
        'file_name': fileName,
        'file_type': mimeType,
        'file_content': base64Content,
        'mime_type': mimeType,
        'category': 'lawyer_verification',
        'description': 'Professional/Bar Council verification document',
      });
      return response.data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // ─── CLIENT REGISTER ─────────────────────
  Future<bool> clientRegister({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    final sw = Stopwatch()..start();
    try {
      final response =
          await DioClient.instance.post('/auth/client/register', data: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
      });
      _logAuthRequest('/auth/client/register', sw,
          statusCode: response.statusCode);
      if (response.data['success'] == true) {
        final data = response.data['data'];
        _token = data['token']?.toString() ?? '';
        _user = UserModel.fromJson(data['user'] ?? {});
        await StorageService.saveToken(_token!);
        await StorageService.saveUser(jsonEncode(_user!.toJson()));
        _status = AuthStatus.authenticated;
        _loading = false;
        notifyListeners();
        FcmService.instance.syncToken();
        return true;
      } else {
        _error = response.data['message'] ?? 'Registration failed';
      }
    } on DioException catch (e) {
      _logAuthRequest('/auth/client/register', sw, error: e);
      _error = _describeAuthError(e);
    } catch (e) {
      _logAuthRequest('/auth/client/register', sw, error: e);
      _error = 'Connection failed. Check internet & backend.';
    }
    _loading = false;
    notifyListeners();
    return false;
  }

  // ─── STUDENT REGISTER ────────────────────
  Future<bool> studentRegister({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String collegeName,
    required String year,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    final sw = Stopwatch()..start();
    try {
      final response =
          await DioClient.instance.post('/auth/student/register', data: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'college_name': collegeName,
        'year': year,
      });
      _logAuthRequest('/auth/student/register', sw,
          statusCode: response.statusCode);
      if (response.data['success'] == true) {
        final data = response.data['data'];
        _token = data['token']?.toString() ?? '';
        _user = UserModel.fromJson(data['user'] ?? {});
        await StorageService.saveToken(_token!);
        await StorageService.saveUser(jsonEncode(_user!.toJson()));
        _status = AuthStatus.authenticated;
        _loading = false;
        notifyListeners();
        FcmService.instance.syncToken();
        return true;
      } else {
        _error = response.data['message'] ?? 'Registration failed';
      }
    } on DioException catch (e) {
      _logAuthRequest('/auth/student/register', sw, error: e);
      _error = _describeAuthError(e);
    } catch (e) {
      _logAuthRequest('/auth/student/register', sw, error: e);
      _error = 'Connection failed. Check internet & backend.';
    }
    _loading = false;
    notifyListeners();
    return false;
  }

  // ─── UPDATE PROFILE ──────────────────────
  // name/phone/designation. Empty strings leave the existing value alone —
  // matches the backend's UpdateProfile, which does the same server-side so
  // a partial edit never blanks out fields the form didn't touch.
  Future<bool> updateProfile(
      {String name = '', String phone = '', String designation = ''}) async {
    if (_user == null) return false;
    try {
      await DioClient.instance.put('/auth/profile', data: {
        'name': name,
        'phone': phone,
        'designation': designation,
      });
      final previous = _user!;
      _user = UserModel(
        id: previous.id,
        name: name.isNotEmpty ? name : previous.name,
        email: previous.email,
        phone: phone.isNotEmpty ? phone : previous.phone,
        roleId: previous.roleId,
        roleName: previous.roleName,
        firmId: previous.firmId,
        avatarUrl: previous.avatarUrl,
        profilePhoto: previous.profilePhoto,
        designation:
            designation.isNotEmpty ? designation : previous.designation,
        isActive: previous.isActive,
        createdAt: previous.createdAt,
      );
      await StorageService.saveUser(jsonEncode(_user!.toJson()));
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── UPDATE PROFILE PHOTO ────────────────
  // Persisted server-side (not just cached on this device) so other users —
  // a client viewing a lawyer's profile, a lawyer viewing a client's — can
  // actually see it, and it survives reinstall/relogin.
  Future<bool> updateProfilePhoto(String base64Photo) async {
    if (_user == null) return false;

    final previous = _user!;
    _user = UserModel(
      id: previous.id,
      name: previous.name,
      email: previous.email,
      phone: previous.phone,
      roleId: previous.roleId,
      roleName: previous.roleName,
      firmId: previous.firmId,
      avatarUrl: base64Photo,
      profilePhoto: base64Photo,
      designation: previous.designation,
      isActive: previous.isActive,
      createdAt: previous.createdAt,
    );
    await StorageService.saveUser(jsonEncode(_user!.toJson()));
    notifyListeners();

    try {
      await DioClient.instance
          .put('/auth/avatar', data: {'avatar_url': base64Photo});
      return true;
    } catch (_) {
      // Keep the local update — it still improves this device's own view —
      // but the caller should tell the user it did not sync.
      return false;
    }
  }

  // ─── LOGOUT ──────────────────────────────
  Future<void> logout() async {
    // Stop the global 3-second auto-refresh immediately — required even
    // though _AutoRefreshGate also reacts to isAuthenticated, since that only
    // runs on the next rebuild; this guarantees no in-flight/queued refresh
    // call fires against a session that's already being torn down below.
    AutoRefreshService.instance.stop();
    await FcmService.instance.clearToken();
    await StorageService.clearAll();
    await TrialService.clear();
    DioClient.reset();
    _user = null;
    _token = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Ends the session because the API rejected the token.
  ///
  /// DioClient calls this on any 401. Without it an expired token left the app
  /// sitting on a fully rendered but empty screen: every request failed, each
  /// provider swallowed the error, and nothing told the user to sign in again.
  void onSessionExpired() {
    if (_status == AuthStatus.unauthenticated) return;
    AutoRefreshService.instance.stop();
    _user = null;
    _token = null;
    _status = AuthStatus.unauthenticated;
    // GoRouter listens to this provider, so the redirect rule sends the user
    // to /login on the next frame.
    notifyListeners();
  }

  // loginAsSuperAdmin() has been removed.
  //
  // It fabricated a super_admin session client-side — a hardcoded user id, a
  // literal 'super-admin-token' string, and AuthStatus.authenticated — without
  // contacting the API at all. Two problems: the credentials that triggered it
  // were compiled into the APK for anyone to extract, and the fake token was
  // rejected by every API call, so the admin panel it unlocked was an empty
  // shell of failing requests.
  //
  // A platform owner now signs in through login() like everyone else, against
  // the super_admin account seeded by database/seeds/seed_roles.sql.
}
