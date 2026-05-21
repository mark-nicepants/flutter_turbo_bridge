import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

void main() {
  group('ScreenshotResult', () {
    test('toString contains relevant info', () {
      final result = ScreenshotResult(
        bytes: Uint8List(1024),
        captureTimeMs: 15,
        width: 390,
        height: 844,
        roundTripMs: 25,
      );
      expect(result.toString(), contains('1024'));
      expect(result.toString(), contains('15'));
      expect(result.toString(), contains('25'));
    });
  });

  group('TapResult', () {
    test('fromJson creates correct instance', () {
      final result = TapResult.fromJson({
        'success': true,
        'executionTimeMs': 2,
      }, 10);

      expect(result.success, isTrue);
      expect(result.executionTimeMs, 2);
      expect(result.roundTripMs, 10);
      expect(result.error, isNull);
    });

    test('fromJson with error', () {
      final result = TapResult.fromJson({
        'success': false,
        'executionTimeMs': 0,
        'error': 'No element at position',
      }, 5);

      expect(result.success, isFalse);
      expect(result.error, 'No element at position');
    });
  });

  group('AppInfo', () {
    test('fromJson creates correct instance', () {
      final info = AppInfo.fromJson({
        'screenWidth': 390.0,
        'screenHeight': 844.0,
        'pixelRatio': 3.0,
        'platform': 'macos',
        'darkMode': true,
        'currentRoute': null,
        'bridgeVersion': '0.1.0',
        'locale': 'nl_NL',
      });

      expect(info.screenWidth, 390.0);
      expect(info.screenHeight, 844.0);
      expect(info.pixelRatio, 3.0);
      expect(info.platform, 'macos');
      expect(info.darkMode, isTrue);
      expect(info.currentRoute, isNull);
      expect(info.bridgeVersion, '0.1.0');
      expect(info.locale, 'nl_NL');
    });

    test('toString contains dimensions', () {
      final info = AppInfo(
        screenWidth: 390,
        screenHeight: 844,
        pixelRatio: 3.0,
        platform: 'ios',
        darkMode: false,
        bridgeVersion: '0.1.0',
      );
      expect(info.toString(), contains('390'));
      expect(info.toString(), contains('844'));
      expect(info.toString(), contains('ios'));
    });
  });
}
