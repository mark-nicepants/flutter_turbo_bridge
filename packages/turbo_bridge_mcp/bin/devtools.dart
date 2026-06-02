import 'dart:io';

import 'package:args/args.dart';
// Import only what the launcher needs — avoid the package umbrella, which
// re-exports the MCP server (and pulls in mcp_dart) and would bloat cold
// start / the `pub global activate` binary.
import 'package:turbo_bridge_mcp/src/adb_forwarding.dart';
import 'package:turbo_bridge_mcp/src/browser.dart';
import 'package:turbo_bridge_mcp/src/devtools_host_server.dart';

/// Standalone launcher for the Turbo Bridge DevTools UI.
///
/// Sets up the (single) ADB forward to the device bridge, serves the DevTools
/// web UI on the host, and opens it in the browser.
///
///   dart run turbo_bridge_mcp:devtools
///   turbo_bridge_devtools            # after `dart pub global activate`
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
      'open',
      defaultsTo: true,
      help: 'Open the DevTools UI in your browser on start',
    )
    ..addFlag('help', negatable: false, help: 'Show usage');

  final results = parser.parse(arguments);
  if (results.flag('help')) {
    stdout.writeln('Turbo Bridge DevTools UI\n');
    stdout.writeln('Usage: turbo_bridge_devtools [options]\n');
    stdout.writeln(parser.usage);
    exit(0);
  }

  final host = results.option('bridge-host')!;
  final bridgePort = int.parse(results.option('bridge-port')!);
  final devToolsPort = int.parse(results.option('devtools-port')!);
  final autoOpen = results.flag('open');

  // Start serving the UI first so it's available immediately — even if the
  // device/adb isn't ready yet (the UI's "Reconnect" button can fix that).
  final server = DevToolsHostServer(
    bridgeHost: host,
    bridgePort: bridgePort,
    projectRoot: results.option('project-root'),
  );
  final int boundPort;
  try {
    boundPort = await server.start(port: devToolsPort);
  } catch (e) {
    stderr.writeln('Failed to start DevTools UI on port $devToolsPort: $e');
    exit(1);
  }

  final url = 'http://localhost:$boundPort/';
  stdout.writeln('Turbo Bridge DevTools UI ready at $url');
  stdout.writeln('  press Ctrl-C to stop');
  if (autoOpen) {
    await openInBrowser(url);
  }

  // Then establish the (single) adb forward to the device bridge.
  final forwarding =
      await ensureBridgeReachable(host: host, bridgePort: bridgePort);
  stdout.writeln('  bridge: $host:$bridgePort${forwarding.summarySuffix}');

  Future<void> shutdown() async {
    await server.stop();
    await forwarding.cleanup();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  ProcessSignal.sigterm.watch().listen((_) => shutdown());
}
