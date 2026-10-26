// Covers the auth request paths touched by the "endless spinner" fix:
// AuthProvider.login/clientRegister must always resolve `loading` back to
// false — on success, on a rejected/duplicate response, on a server error,
// and on a connection timeout — and must never silently swallow a failure.
//
// Requests are faked with a custom HttpClientAdapter instead of a real
// network call, so these tests exercise DioClient's interceptors and
// AuthProvider's response handling exactly as production does, without
// depending on the actual Render backend being reachable.

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:libra_law/core/services/dio_client.dart';
import 'package:libra_law/features/auth/providers/auth_provider.dart';

/// Minimal fake transport: the test supplies one `handler` per case instead
/// of this adapter guessing response shapes.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);
}

ResponseBody _jsonBody(Map<String, dynamic> data, int statusCode) {
  return ResponseBody.fromString(
    jsonEncodeForTest(data),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

// Avoids pulling in dart:convert just for one call site, while keeping this
// file self-contained and obvious about what it sends.
String jsonEncodeForTest(Map<String, dynamic> data) {
  final buffer = StringBuffer('{');
  var first = true;
  data.forEach((key, value) {
    if (!first) buffer.write(',');
    first = false;
    buffer.write('"$key":');
    if (value is String) {
      buffer.write('"${value.replaceAll('"', r'\"')}"');
    } else if (value is Map) {
      buffer.write(jsonEncodeForTest(value.cast<String, dynamic>()));
    } else if (value == null) {
      buffer.write('null');
    } else {
      buffer.write(value);
    }
  });
  buffer.write('}');
  return buffer.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AuthProvider persists the session via StorageService, which uses
  // flutter_secure_storage (a platform channel) and SharedPreferences.
  // Neither has a real platform to talk to under `flutter test`, so both are
  // stubbed — this is test plumbing, not a change to how the app persists a
  // session on-device.
  const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStore = <String, String>{};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
      switch (call.method) {
        case 'write':
          final args = call.arguments as Map;
          secureStore[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          final args = call.arguments as Map;
          return secureStore[args['key'] as String];
        case 'readAll':
          return secureStore;
        case 'delete':
          final args = call.arguments as Map;
          secureStore.remove(args['key'] as String);
          return null;
        case 'deleteAll':
          secureStore.clear();
          return null;
        case 'containsKey':
          final args = call.arguments as Map;
          return secureStore.containsKey(args['key'] as String);
      }
      return null;
    });
    DioClient.reset();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    DioClient.reset();
  });

  group('AuthProvider.login', () {
    test('success resets loading, stores the session, and returns true', () async {
      DioClient.instance.httpClientAdapter = _FakeAdapter((options) async {
        expect(options.path, '/auth/login');
        return _jsonBody({
          'success': true,
          'message': 'Login successful',
          'data': {
            'token': 'test-token',
            'user': {'id': 'u1', 'name': 'Jyoti', 'email': 'j@x.com', 'role_name': 'client'},
          },
        }, 200);
      });

      final auth = AuthProvider();
      final result = await auth.login('j@x.com', 'password', 'client');

      expect(result, isTrue);
      expect(auth.loading, isFalse);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.error, isNull);
    });

    test('invalid credentials resets loading and surfaces the server message', () async {
      DioClient.instance.httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 401,
            data: {'success': false, 'message': 'Invalid email or password'},
          ),
        );
      });

      final auth = AuthProvider();
      final result = await auth.login('j@x.com', 'wrong', 'client');

      expect(result, isFalse);
      expect(auth.loading, isFalse);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.error, 'Invalid email or password');
    });

    test('a connection timeout resets loading and shows a timeout message, not a raw exception',
        () async {
      DioClient.instance.httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      });

      final auth = AuthProvider();
      final result = await auth.login('j@x.com', 'password', 'client');

      expect(result, isFalse);
      expect(auth.loading, isFalse);
      expect(auth.error, contains('too long'));
      expect(auth.error, isNot(contains('DioException')));
    });

    test('an unreachable server resets loading and shows a connectivity message', () async {
      DioClient.instance.httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });

      final auth = AuthProvider();
      final result = await auth.login('j@x.com', 'password', 'client');

      expect(result, isFalse);
      expect(auth.loading, isFalse);
      expect(auth.error, contains('Could not reach the server'));
    });

    test('a 500 response resets loading and shows a server-side message', () async {
      DioClient.instance.httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 500,
            data: {'success': false},
          ),
        );
      });

      final auth = AuthProvider();
      final result = await auth.login('j@x.com', 'password', 'client');

      expect(result, isFalse);
      expect(auth.loading, isFalse);
      expect(auth.error, contains('server had a problem'));
    });
  });

  group('AuthProvider.clientRegister', () {
    test('success resets loading, stores the session, and returns true', () async {
      DioClient.instance.httpClientAdapter = _FakeAdapter((options) async {
        expect(options.path, '/auth/client/register');
        return _jsonBody({
          'success': true,
          'message': 'Account created',
          'data': {
            'token': 'test-token',
            'user': {'id': 'c1', 'name': 'jyoti', 'email': 'jyoti@gmail.com', 'role_name': 'client'},
          },
        }, 201);
      });

      final auth = AuthProvider();
      final result = await auth.clientRegister(
        name: 'jyoti',
        email: 'jyoti@gmail.com',
        phone: '9082164622',
        password: 'Jyoti@0921',
      );

      expect(result, isTrue);
      expect(auth.loading, isFalse);
      expect(auth.isAuthenticated, isTrue);
    });

    test('a duplicate account resets loading and surfaces the server message', () async {
      DioClient.instance.httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 409,
            data: {'success': false, 'message': 'An account with this email already exists'},
          ),
        );
      });

      final auth = AuthProvider();
      final result = await auth.clientRegister(
        name: 'jyoti',
        email: 'jyoti@gmail.com',
        phone: '9082164622',
        password: 'Jyoti@0921',
      );

      expect(result, isFalse);
      expect(auth.loading, isFalse);
      expect(auth.error, 'An account with this email already exists');
    });

    test('a validation failure resets loading and surfaces the server message', () async {
      DioClient.instance.httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 400,
            data: {'success': false, 'message': 'Phone number is invalid'},
          ),
        );
      });

      final auth = AuthProvider();
      final result = await auth.clientRegister(
        name: 'jyoti',
        email: 'jyoti@gmail.com',
        phone: '123',
        password: 'Jyoti@0921',
      );

      expect(result, isFalse);
      expect(auth.loading, isFalse);
      expect(auth.error, 'Phone number is invalid');
    });

    test('a timeout during registration resets loading instead of spinning forever', () async {
      DioClient.instance.httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      });

      final auth = AuthProvider();
      final result = await auth.clientRegister(
        name: 'jyoti',
        email: 'jyoti@gmail.com',
        phone: '9082164622',
        password: 'Jyoti@0921',
      );

      expect(result, isFalse);
      expect(auth.loading, isFalse);
      expect(auth.error, contains('too long'));
    });

    test('an unparseable response resets loading instead of throwing past the caller', () async {
      DioClient.instance.httpClientAdapter = _FakeAdapter((options) async {
        // Dio's json transformer fails on this, raising a generic error that
        // must still land in the catch-all branch and reset loading.
        return ResponseBody.fromString(
          'not json',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final auth = AuthProvider();
      final result = await auth.clientRegister(
        name: 'jyoti',
        email: 'jyoti@gmail.com',
        phone: '9082164622',
        password: 'Jyoti@0921',
      );

      expect(result, isFalse);
      expect(auth.loading, isFalse);
      expect(auth.error, isNotNull);
    });
  });
}
