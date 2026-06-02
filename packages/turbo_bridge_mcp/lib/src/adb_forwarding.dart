import 'dart:convert';
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

typedef BridgeInfoLoader = Future<Map<String, dynamic>?> Function(
  String host,
  int port,
);

class AdbForwardingSession {
  AdbForwardingSession({
    required this.bridgeForwarded,
    required this.devToolsForwarded,
    required this.devToolsPort,
    required Set<int> forwardedPorts,
    required ProcessRunner processRunner,
  })  : _forwardedPorts = List<int>.unmodifiable(forwardedPorts),
        _processRunner = processRunner;

  final bool bridgeForwarded;
  final bool devToolsForwarded;
  final int? devToolsPort;
  final List<int> _forwardedPorts;
  final ProcessRunner _processRunner;

  bool get hasForwarding => _forwardedPorts.isNotEmpty;

  String get summarySuffix {
    if (!hasForwarding) {
      return '';
    }

    final details = <String>[];
    if (bridgeForwarded && _forwardedPorts.isNotEmpty) {
      details.add('bridge=${_forwardedPorts.first}');
    }
    if (devToolsForwarded && devToolsPort != null) {
      details.add('devtools=$devToolsPort');
    }

    return details.isEmpty
        ? ', adb forwarded'
        : ', adb forwarded ${details.join(', ')}';
  }

  Future<void> cleanup() async {
    for (final port in _forwardedPorts.reversed) {
      await _removeAdbForward(port, processRunner: _processRunner);
    }
  }
}

Future<AdbForwardingSession> ensureBridgeAndDevToolsReachable({
  required String host,
  required int bridgePort,
  ProcessRunner processRunner = _runProcess,
  HttpReachabilityProbe reachabilityProbe = _canReachHttpEndpoint,
  BridgeInfoLoader bridgeInfoLoader = _loadBridgeInfo,
}) async {
  final forwardedPorts = <int>{};
  var bridgeForwarded = false;
  var devToolsForwarded = false;
  int? devToolsPort;

  AdbEnvironment? adbEnvironment;

  Future<AdbEnvironment> loadAdbEnvironment() async {
    adbEnvironment ??=
        await _detectAdbEnvironment(processRunner: processRunner);
    return adbEnvironment!;
  }

  var bridgeReachable = await reachabilityProbe(host, bridgePort, '/health');
  if (!bridgeReachable) {
    final adb = await loadAdbEnvironment();
    if (!adb.isAvailable) {
      stderr.writeln(
        'Bridge not reachable at $host:$bridgePort (no ADB available)',
      );
      return AdbForwardingSession(
        bridgeForwarded: false,
        devToolsForwarded: false,
        devToolsPort: null,
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
        devToolsForwarded: false,
        devToolsPort: null,
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
      bridgeReachable = await reachabilityProbe(host, bridgePort, '/health');
      if (!bridgeReachable) {
        stderr.writeln(
          'ADB forward set up but bridge not responding on device:$bridgePort',
        );
      }
    }
  }

  if (!bridgeReachable) {
    return AdbForwardingSession(
      bridgeForwarded: bridgeForwarded,
      devToolsForwarded: false,
      devToolsPort: null,
      forwardedPorts: forwardedPorts,
      processRunner: processRunner,
    );
  }

  final info = await bridgeInfoLoader(host, bridgePort);
  devToolsPort = _extractEnabledDevToolsPort(info);
  if (devToolsPort != null && !forwardedPorts.contains(devToolsPort)) {
    final devToolsReachable = await reachabilityProbe(
      '127.0.0.1',
      devToolsPort,
      '/',
    );

    if (!devToolsReachable) {
      final adb = await loadAdbEnvironment();
      if (!adb.isAvailable) {
        stderr.writeln(
          'DevTools UI not reachable at localhost:$devToolsPort '
          '(no ADB available)',
        );
      } else if (!adb.hasConnectedDevice) {
        stderr.writeln(
          'DevTools UI not reachable at localhost:$devToolsPort '
          '(no Android device connected)',
        );
      } else if (await _addAdbForward(
        devToolsPort,
        processRunner: processRunner,
      )) {
        devToolsForwarded = true;
        forwardedPorts.add(devToolsPort);
        stderr.writeln(
          'ADB forward established: localhost:$devToolsPort '
          '-> device:$devToolsPort (DevTools UI)',
        );
        if (!await reachabilityProbe('127.0.0.1', devToolsPort, '/')) {
          stderr.writeln(
            'ADB forward set up but DevTools UI not responding '
            'on device:$devToolsPort',
          );
        }
      }
    }
  }

  return AdbForwardingSession(
    bridgeForwarded: bridgeForwarded,
    devToolsForwarded: devToolsForwarded,
    devToolsPort: devToolsPort,
    forwardedPorts: forwardedPorts,
    processRunner: processRunner,
  );
}

Future<AdbEnvironment> _detectAdbEnvironment({
  required ProcessRunner processRunner,
}) async {
  final adbCheck = await processRunner('adb', ['devices']);
  if (adbCheck.exitCode != 0) {
    return const AdbEnvironment(isAvailable: false, hasConnectedDevice: false);
  }

  final hasConnectedDevice = (adbCheck.stdout as String)
      .split('\n')
      .any((line) => line.contains('\tdevice'));

  return AdbEnvironment(
    isAvailable: true,
    hasConnectedDevice: hasConnectedDevice,
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

int? _extractEnabledDevToolsPort(Map<String, dynamic>? info) {
  final devTools = info?['devTools'];
  if (devTools is! Map<String, dynamic>) {
    return null;
  }
  if (devTools['enabled'] != true) {
    return null;
  }
  final port = devTools['port'];
  if (port is int) {
    return port;
  }
  if (port is num) {
    return port.toInt();
  }
  return null;
}

Future<Map<String, dynamic>?> _loadBridgeInfo(String host, int port) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(Uri.parse('http://$host:$port/info'));
    final response = await request.close();
    if (response.statusCode != 200) {
      return null;
    }

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body);
    return json is Map<String, dynamic> ? json : null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
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
