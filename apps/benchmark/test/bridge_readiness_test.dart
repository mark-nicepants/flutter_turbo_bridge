import 'package:flutter_turbo_bridge_benchmark/src/bridge_readiness.dart';
import 'package:test/test.dart';

void main() {
  group('waitForBridge', () {
    test('retries until the bridge becomes reachable', () async {
      var attempts = 0;

      final ready = await waitForBridge(
        isConnected: () async {
          attempts++;
          return attempts >= 3;
        },
        timeout: const Duration(milliseconds: 20),
        retryInterval: const Duration(milliseconds: 1),
      );

      expect(ready, isTrue);
      expect(attempts, 3);
    });

    test('returns false when the startup window expires', () async {
      var attempts = 0;

      final ready = await waitForBridge(
        isConnected: () async {
          attempts++;
          return false;
        },
        timeout: const Duration(milliseconds: 5),
        retryInterval: const Duration(milliseconds: 1),
      );

      expect(ready, isFalse);
      expect(attempts, greaterThanOrEqualTo(1));
    });

    test('keeps retrying after transient errors', () async {
      var attempts = 0;

      final ready = await waitForBridge(
        isConnected: () async {
          attempts++;
          if (attempts < 3) {
            throw StateError('not ready');
          }
          return true;
        },
        timeout: const Duration(milliseconds: 20),
        retryInterval: const Duration(milliseconds: 1),
      );

      expect(ready, isTrue);
      expect(attempts, 3);
    });
  });
}
