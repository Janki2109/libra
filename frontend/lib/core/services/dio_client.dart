import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import 'storage_service.dart';

/// Shared HTTP client.
class DioClient {
  static Dio? _dio;

  /// Invoked when the API rejects the session. The app installs a callback here
  /// to send the user back to the login screen.
  ///
  /// Without this the app silently rendered empty screens once a token
  /// expired: every request came back 401, the interceptor passed it straight
  /// through, and the user saw an app with no data and no explanation.
  static void Function()? onUnauthorized;

  static Dio get instance {
    _dio ??= _createDio();
    return _dio!;
  }

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(milliseconds: AppConstants.connectTimeout),
      receiveTimeout: const Duration(milliseconds: AppConstants.receiveTimeout),
      sendTimeout: const Duration(milliseconds: AppConstants.sendTimeout),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      // Treat only 2xx as success so error bodies land in onError in one place
      // rather than each caller having to inspect the status itself.
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Reads from secure storage now — the token is no longer kept in
        // SharedPreferences. See StorageService.
        final token = await StorageService.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // The session is gone — drop the dead token and hand control back to
          // the app so it can show the login screen.
          await StorageService.clearAll();
          onUnauthorized?.call();
        }
        return handler.next(error);
      },
    ));

    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        request: true,
        requestBody: true,
        responseBody: true,
        // Never log headers: they carry the bearer token, and this output is
        // visible to anything reading the device log.
        requestHeader: false,
        responseHeader: false,
      ));

      if (AppConstants.isInsecureEndpoint) {
        debugPrint(
          '[DioClient] API_BASE_URL is plain http:// — fine for a local '
          'emulator, never for a build you ship.',
        );
      }
    }

    return dio;
  }

  /// Rebuild the client — call after login or logout so the next request picks
  /// up the new token state.
  static void reset() {
    _dio?.close(force: true);
    _dio = null;
  }

  /// Turns a Dio failure into something worth showing a user.
  ///
  /// Screens previously surfaced `error.toString()`, which renders as
  /// "DioException [connection error]: ..." — meaningless to a lawyer trying to
  /// open a case file, and it leaks the API host into the UI.
  static String describeError(Object error) {
    if (error is! DioException) {
      return 'Something went wrong. Please try again.';
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The server took too long to respond. Check your connection and try again.';
      case DioExceptionType.connectionError:
        return 'Could not reach the server. Check your internet connection.';
      case DioExceptionType.badCertificate:
        return "The server's security certificate could not be verified.";
      case DioExceptionType.cancel:
        return 'Request cancelled.';
      case DioExceptionType.badResponse:
        final data = error.response?.data;
        if (data is Map && data['message'] is String) {
          return data['message'] as String;
        }
        final code = error.response?.statusCode;
        if (code == 401) {
          return 'Your session has expired. Please sign in again.';
        }
        if (code == 403) return 'You do not have access to that.';
        if (code == 404) return 'Not found.';
        if (code == 409) {
          return 'That conflicts with something that already exists.';
        }
        if (code == 429) {
          return 'Too many attempts. Please wait a moment and try again.';
        }
        if (code != null && code >= 500) {
          return 'The server had a problem. Please try again shortly.';
        }
        return 'Request failed. Please try again.';
      case DioExceptionType.unknown:
        return 'Something went wrong. Please try again.';
    }
  }
}
