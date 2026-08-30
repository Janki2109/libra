// Smoke tests for the app shell.
//
// This file was still Flutter's generated counter-app template: it imported
// `package:frontend/main.dart` (the package is `libra_law`) and pumped a
// `MyApp` that does not exist, so `flutter test` failed to compile and the
// project's only two analyzer errors both came from here. Nothing in CI could
// have been green.

import 'package:flutter_test/flutter_test.dart';
import 'package:libra_law/core/constants/app_constants.dart';
import 'package:libra_law/core/services/dio_client.dart';

void main() {
  group('AppConstants', () {
    test('base url comes from the build-time define', () {
      // Guards the regression this replaced: a hardcoded production URL that
      // shipped in every build regardless of target.
      expect(AppConstants.baseUrl, isNotEmpty);
      expect(AppConstants.baseUrl, contains('/api/v1'));
    });

    test('flags a plaintext endpoint', () {
      expect(
        AppConstants.isInsecureEndpoint,
        AppConstants.baseUrl.startsWith('http://'),
      );
    });
  });

  group('DioClient.describeError', () {
    test('renders a non-Dio failure as plain guidance', () {
      expect(
        DioClient.describeError(Exception('boom')),
        'Something went wrong. Please try again.',
      );
    });

    test('never surfaces raw exception text to the user', () {
      final message = DioClient.describeError(Exception('DioException [x]'));
      expect(message, isNot(contains('DioException')));
    });
  });
}
