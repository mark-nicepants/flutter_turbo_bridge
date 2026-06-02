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
      'devtools',
      defaultsTo: true,
      help: 'Serve the DevTools web UI on this host',
    )
    ..addOption(
      'devtools-port',
      defaultsTo: '8889',
      help: 'Local port to serve the DevTools UI on',
    )
    ..addOption(
      'project-root',
      help: 'Flutter project dir for resolving package: source links '
          '(defaults to the current directory)',
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

  // Auto-detect: try direct connection, fall back to ADB forwarding.
  final forwarding = await ensureBridgeReachable(host: host, bridgePort: port);

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

  // Serve the DevTools UI on the host (no auto-open — the agent may
  // reconnect often; the URL is logged instead).
  DevToolsHostServer? devTools;
  if (results.flag('devtools')) {
    final devToolsPort = int.parse(results.option('devtools-port')!);
    devTools = DevToolsHostServer(
      bridgeHost: host,
      bridgePort: port,
      projectRoot: results.option('project-root'),
    );
    try {
      final bound = await devTools.start(port: devToolsPort);
      stderr.writeln(
        'Turbo Bridge DevTools UI ready at http://localhost:$bound/',
      );
    } catch (e) {
      stderr.writeln('DevTools UI failed to start on port $devToolsPort: $e');
      devTools = null;
    }
  }

  final adbInfo = forwarding.summarySuffix;
  stderr
      .writeln('Turbo Bridge MCP server started (bridge=$host:$port$adbInfo)');

  // Clean up on exit.
  Future<void> shutdown() async {
    await devTools?.stop();
    if (forwarding.hasForwarding) {
      await forwarding.cleanup();
    }
    exit(0);
  }

  if (forwarding.hasForwarding || devTools != null) {
    ProcessSignal.sigint.watch().listen((_) => shutdown());
    ProcessSignal.sigterm.watch().listen((_) => shutdown());
  }
}
