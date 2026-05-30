import 'dart:async';

const Duration defaultBridgeStartupTimeout = Duration(seconds: 30);
const Duration defaultBridgeRetryInterval = Duration(milliseconds: 500);

Future<bool> waitForBridge({
  required Future<bool> Function() isConnected,
  Duration timeout = defaultBridgeStartupTimeout,
  Duration retryInterval = defaultBridgeRetryInterval,
}) async {
  final deadline = DateTime.now().add(timeout);

  while (true) {
    try {
      if (await isConnected()) {
        return true;
      }
    } catch (_) {
      // Keep retrying until the startup window closes.
    }

    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return false;
    }

    final delay = remaining < retryInterval ? remaining : retryInterval;
    await Future<void>.delayed(delay);
  }
}
