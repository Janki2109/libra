import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/trial_service.dart';
import '../models/auth_model.dart';

/// Turns a login failure into the right message for the right cause, instead
/// of the previous blanket "Login failed. Check credentials." for every
/// DioException — which made a release build pointed at an unreachable API
/// (e.g. still compiled with the default localhost base URL) look exactly
/// like a wrong password, with nothing in the UI to tell them apart.
///
/// Only a real 401/400 response with a credentials-shaped message is shown
/// as a credentials error; every network-level failure (no connection, DNS,
/// timeout, TLS, 5xx) gets its own distinct, honest message instead.
String _describeLoginError(DioException e) {
  final data = e.response?.data;
  if (data is Map && data['message'] is String) {
    // The backend actually answered — this is a real auth/validation
    // rejection, not a connectivity problem.
    return data['message'] as String;
  }
  return DioClient.describeError(e);
}

void _logLoginFailure(String endpoint, Object error) {
  // Never logs email/password — only the target URL and what Dio/the server
  // said, so a "works locally, fails in the APK" report can be diagnosed
  // from `adb logcat` without needing repro access to the failing device.
  if (error is DioException) {
    debugPrint('[auth] POST $endpoint -> ${AppConstants.baseUrl} failed: '
        'type=${error.type} status=${error.response?.statusCode}');
  } else {
    debugPrint('[auth] POST $endpoint -> ${AppConstants.baseUrl} failed: $error');
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
  Future<bool> login(String email, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await DioClient.instance.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
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
      _logLoginFailure('/auth/login', e);
      _error = _describeLoginError(e);
    } catch (e) {
      _logLoginFailure('/auth/login', e);
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
    try {
      final response = await DioClient.instance.post('/portal/login', data: {
        'email': email,
        'password': password,
      });
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
      _logLoginFailure('/portal/login', e);
      _error = _describeLoginError(e);
    } catch (e) {
      _logLoginFailure('/portal/login', e);
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
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
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
      });

      if (response.data['success'] == true) {
        final data = response.data['data'];
        _token = data['token']?.toString() ?? '';
        _user = UserModel(
          id: data['user_id']?.toString() ?? '',
          name: name,
          email: email,
          phone: phone,
          roleName: 'admin',
          firmId: data['firm_id']?.toString() ?? '',
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
      _error = e.response?.data['message'] ?? 'Registration failed';
    } catch (e) {
      _error = e.toString();
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
      final response = await DioClient.instance.post('/documents/upload', data: {
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
    try {
      final response =
          await DioClient.instance.post('/auth/client/register', data: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
      });
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
      _error = e.response?.data['message'] ?? 'Registration failed';
    } catch (e) {
      _error = e.toString();
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
      _error = e.response?.data['message'] ?? 'Registration failed';
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
    return false;
  }

  // ─── UPDATE PROFILE PHOTO ────────────────
  Future<void> updateProfilePhoto(String base64Photo) async {
    if (_user == null) return;
    _user = UserModel(
      id: _user!.id,
      name: _user!.name,
      email: _user!.email,
      phone: _user!.phone,
      roleId: _user!.roleId,
      roleName: _user!.roleName,
      firmId: _user!.firmId,
      avatarUrl: _user!.avatarUrl,
      profilePhoto: base64Photo,
      designation: _user!.designation,
      isActive: _user!.isActive,
      createdAt: _user!.createdAt,
    );
    await StorageService.saveUser(jsonEncode(_user!.toJson()));
    notifyListeners();
  }

  // ─── LOGOUT ──────────────────────────────
  Future<void> logout() async {
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
