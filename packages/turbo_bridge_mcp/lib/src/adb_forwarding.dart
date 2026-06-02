import 'dart:io';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

typedef HttpReachabilityProbe = Future<bool> Function(
  String host,
  int port,
  String path,
);

/// Result of trying to make the device bridge reachable from the host.
///
/// Since the DevTools UI now runs on the host (not the device), only the
/// single bridge port needs forwarding.
class AdbForwardingSession {
  AdbForwardingSession({
    required this.bridgeForwarded,
    required Set<int> forwardedPorts,
    required ProcessRunner processRunner,
  })  : _forwardedPorts = List<int>.unmodifiable(forwardedPorts),
        _processRunner = processRunner;

  final bool bridgeForwarded;
  final List<int> _forwardedPorts;
  final ProcessRunner _processRunner;

  bool get hasForwarding => _forwardedPorts.isNotEmpty;

  String get summarySuffix {
    if (!hasForwarding) {
      return '';
    }
    return ', adb forwarded ${_forwardedPorts.first}';
  }

  Future<void> cleanup() async {
    for (final port in _forwardedPorts.reversed) {
      await _removeAdbForward(port, processRunner: _processRunner);
    }
  }
}

/// Ensure the device bridge is reachable at [host]:[bridgePort], setting up an
/// `adb forward` for that single port if a direct connection fails.
Future<AdbForwardingSession> ensureBridgeReachable({
  required String host,
  required int bridgePort,
  ProcessRunner processRunner = _runProcess,
  HttpReachabilityProbe reachabilityProbe = _canReachHttpEndpoint,
}) async {
  final forwardedPorts = <int>{};
  var bridgeForwarded = false;

  var reachable = await reachabilityProbe(host, bridgePort, '/health');
  if (!reachable) {
    final adb = await _detectAdbEnvironment(processRunner: processRunner);
    if (!adb.isAvailable) {
      stderr.writeln(
        'Bridge not reachable at $host:$bridgePort (no ADB available)',
      );
      return AdbForwardingSession(
        bridgeForwarded: false,
        forwardedPorts: forwardedPorts,
        processRunner: processRunner,
      );
    }
    if (!adb.hasConnectedDevice) {
      stderr.writeln(
        'Bridge not reachable at $host:$bridgePort '
        '(no Android device connected)',
      );
      return AdbForwardingSession(
        bridgeForwarded: false,
        forwardedPorts: forwardedPorts,
        processRunner: processRunner,
      );
    }

    if (await _addAdbForward(bridgePort, processRunner: processRunner)) {
      bridgeForwarded = true;
      forwardedPorts.add(bridgePort);
      stderr.writeln(
        'ADB forward established: localhost:$bridgePort -> device:$bridgePort',
      );
      reachable = await reachabilityProbe(host, bridgePort, '/health');
      if (!reachable) {
        stderr.writeln(
          'ADB forward set up but bridge not responding on device:$bridgePort',
        );
      }
    }
  }

  return AdbForwardingSession(
    bridgeForwarded: bridgeForwarded,
    forwardedPorts: forwardedPorts,
    processRunner: processRunner,
  );
}

Future<AdbEnvironment> _detectAdbEnvironment({
  required ProcessRunner processRunner,
}) async {
  try {
    final adbCheck = await processRunner('adb', ['devices']);
    if (adbCheck.exitCode != 0) {
      return const AdbEnvironment(
          isAvailable: false, hasConnectedDevice: false);
    }

    final hasConnectedDevice = (adbCheck.stdout as String)
        .split('\n')
        .any((line) => line.contains('\tdevice'));

    return AdbEnvironment(
      isAvailable: true,
      hasConnectedDevice: hasConnectedDevice,
    );
  } catch (_) {
    // adb binary not on PATH (Process.run throws) — treat as unavailable.
    return const AdbEnvironment(isAvailable: false, hasConnectedDevice: false);
  }
}

/// Snapshot of bridge reachability + the local ADB environment, returned by
/// [probeBridgeStatus] / [reconnectBridge] and surfaced to the DevTools UI so
/// it can offer a one-click reconnect.
class BridgeReconnectStatus {
  const BridgeReconnectStatus({
    required this.bridgeReachable,
    required this.adbAvailable,
    required this.deviceConnected,
    this.forwarded = false,
    this.message = '',
  });

  final bool bridgeReachable;
  final bool adbAvailable;
  final bool deviceConnected;
  final bool forwarded;
  final String message;

  BridgeReconnectStatus copyWith({
    bool? bridgeReachable,
    bool? forwarded,
    String? message,
  }) =>
      BridgeReconnectStatus(
        bridgeReachable: bridgeReachable ?? this.bridgeReachable,
        adbAvailable: adbAvailable,
        deviceConnected: deviceConnected,
        forwarded: forwarded ?? this.forwarded,
        message: message ?? this.message,
      );

  Map<String, dynamic> toJson() => {
        'bridgeReachable': bridgeReachable,
        'adbAvailable': adbAvailable,
        'deviceConnected': deviceConnected,
        'forwarded': forwarded,
        'message': message,
      };
}

/// Probe whether the bridge is reachable and what the local ADB environment
/// looks like — without changing anything.
Future<BridgeReconnectStatus> probeBridgeStatus({
  required String host,
  required int bridgePort,
  ProcessRunner? processRunner,
  HttpReachabilityProbe? reachabilityProbe,
}) async {
  final runner = processRunner ?? _runProcess;
  final probe = reachabilityProbe ?? _canReachHttpEndpoint;
  final reachable = await probe(host, bridgePort, '/health');
  final adb = await _detectAdbEnvironment(processRunner: runner);
  return BridgeReconnectStatus(
    bridgeReachable: reachable,
    adbAvailable: adb.isAvailable,
    deviceConnected: adb.hasConnectedDevice,
    message: reachable ? 'Bridge reachable.' : 'Bridge not reachable.',
  );
}

/// Best-effort reconnect: if the bridge isn't reachable, (re)establish the
/// `adb forward tcp:<bridgePort>` and re-probe. Safe to call repeatedly —
/// this is what the DevTools UI's "Reconnect" button triggers.
Future<BridgeReconnectStatus> reconnectBridge({
  required String host,
  required int bridgePort,
  ProcessRunner? processRunner,
  HttpReachabilityProbe? reachabilityProbe,
}) async {
  final runner = processRunner ?? _runProcess;
  final probe = reachabilityProbe ?? _canReachHttpEndpoint;
  final status = await probeBridgeStatus(
    host: host,
    bridgePort: bridgePort,
    processRunner: runner,
    reachabilityProbe: probe,
  );
  if (status.bridgeReachable) {
    return status.copyWith(message: 'Bridge already reachable.');
  }
  if (!status.adbAvailable) {
    return status.copyWith(
      message: 'ADB not found on PATH. Install platform-tools, or run the '
          'app on this machine so the bridge is reachable on localhost.',
    );
  }
  if (!status.deviceConnected) {
    return status.copyWith(
      message: 'No Android device detected by adb. Plug in / reconnect the '
          'device and try again.',
    );
  }
  final ok = await _addAdbForward(bridgePort, processRunner: runner);
  if (!ok) {
    return status.copyWith(message: 'adb forward failed — see server logs.');
  }
  final reachable = await probe(host, bridgePort, '/health');
  return status.copyWith(
    bridgeReachable: reachable,
    forwarded: true,
    message: reachable
        ? 'ADB forward established — reconnected.'
        : 'Forward set up but the bridge is not responding yet. Is the app '
            'running with DevTools enabled?',
  );
}

Future<bool> _addAdbForward(
  int port, {
  required ProcessRunner processRunner,
}) async {
  final result =
      await processRunner('adb', ['forward', 'tcp:$port', 'tcp:$port']);
  if (result.exitCode == 0) {
    return true;
  }

  stderr.writeln('ADB forward failed: ${result.stderr.toString().trim()}');
  return false;
}

Future<void> _removeAdbForward(
  int port, {
  required ProcessRunner processRunner,
}) async {
  await processRunner('adb', ['forward', '--remove', 'tcp:$port']);
  stderr.writeln('ADB forward removed for port $port');
}

Future<bool> _canReachHttpEndpoint(String host, int port, String path) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(Uri.parse('http://$host:$port$path'));
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode >= 200 && response.statusCode < 400;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments,
) {
  return Process.run(executable, arguments);
}

class AdbEnvironment {
  const AdbEnvironment({
    required this.isAvailable,
    required this.hasConnectedDevice,
  });

  final bool isAvailable;
  final bool hasConnectedDevice;
}
