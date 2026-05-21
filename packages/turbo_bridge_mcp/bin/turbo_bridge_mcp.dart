import 'dart:io';

import 'package:args/args.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';
import 'package:turbo_bridge_mcp/turbo_bridge_mcp.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'bridge-host',
      abbr: 'h',
      defaultsTo: 'localhost',
      help: 'Turbo Bridge host address',
    )
    ..addOption(
      'bridge-port',
      abbr: 'p',
      defaultsTo: '8888',
      help: 'Turbo Bridge HTTP port',
    )
    ..addOption(
      'vm-uri',
      help: 'Dart VM Service URI (optional, for evaluation)',
    )
    ..addFlag(
      'help',
      negatable: false,
      help: 'Show usage',
    );

  final results = parser.parse(arguments);

  if (results.flag('help')) {
    stderr.writeln('Flutter Turbo Bridge MCP Server\n');
    stderr.writeln('Usage: turbo_bridge_mcp [options]\n');
    stderr.writeln(parser.usage);
    exit(0);
  }

  final host = results.option('bridge-host')!;
  final port = int.parse(results.option('bridge-port')!);
  final vmUri = results.option('vm-uri');

  // Auto-detect: try direct connection, fall back to ADB forwarding
  final adbForwarded = await _ensureBridgeReachable(host, port);

  // Create the client
  final TurboBridgeClient client;
  if (vmUri != null) {
    client = TurboBridgeClient.withVmService(
      host: host,
      port: port,
      vmServiceUri: vmUri,
    );
  } else {
    client = TurboBridgeClient(host: host, port: port);
  }

  // Create and start the MCP server over stdio
  final server = createMcpServer(client: client);

  final transport = StdioServerTransport();
  await server.connect(transport);

  final adbInfo = adbForwarded ? ', adb forwarded' : '';
  stderr.writeln('Turbo Bridge MCP server started (bridge=$host:$port$adbInfo)');

  // Clean up ADB forwarding on exit
  if (adbForwarded) {
    ProcessSignal.sigint.watch().listen((_) async {
      await _removeAdbForward(port);
      exit(0);
    });
    ProcessSignal.sigterm.watch().listen((_) async {
      await _removeAdbForward(port);
      exit(0);
    });
  }
}

/// Try to reach the bridge directly. If unreachable, check for an Android
/// device via ADB and set up port forwarding automatically.
/// Returns true if ADB forwarding was established.
Future<bool> _ensureBridgeReachable(String host, int port) async {
  // Try direct connection first
  if (await _canReachBridge(host, port)) {
    return false;
  }

  // Bridge not reachable — check if ADB is available
  final adbCheck = await Process.run('adb', ['devices']);
  if (adbCheck.exitCode != 0) {
    // No ADB available, continue without forwarding
    stderr.writeln(
      'Bridge not reachable at $host:$port (no ADB available)',
    );
    return false;
  }

  // Check if any Android device is connected
  final lines = (adbCheck.stdout as String).split('\n').where((l) => l.contains('\tdevice')).toList();

  if (lines.isEmpty) {
    stderr.writeln(
      'Bridge not reachable at $host:$port (no Android device connected)',
    );
    return false;
  }

  // Set up ADB port forwarding
  final result = await Process.run('adb', ['forward', 'tcp:$port', 'tcp:$port']);
  if (result.exitCode != 0) {
    stderr.writeln('ADB forward failed: ${result.stderr.toString().trim()}');
    return false;
  }

  stderr.writeln('ADB forward established: localhost:$port -> device:$port');

  // Verify the bridge is now reachable through the forward
  if (!await _canReachBridge(host, port)) {
    stderr.writeln(
      'ADB forward set up but bridge not responding on device:$port',
    );
  }

  return true;
}

Future<bool> _canReachBridge(String host, int port) async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    final request = await client.getUrl(Uri.parse('http://$host:$port/health'));
    final response = await request.close();
    await response.drain<void>();
    client.close();
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

Future<void> _removeAdbForward(int port) async {
  await Process.run('adb', ['forward', '--remove', 'tcp:$port']);
  stderr.writeln('ADB forward removed for port $port');
}
