import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

import '../response_metadata.dart';

/// Registers the `flutter_recent_network` tool: returns network calls that
/// the running app recorded into TurboBridge.instance.network. Useful for
/// auditing what the app talks to without needing OS-level network proxies.
void registerRecentNetworkTool(McpServer server, TurboBridgeClient client) {
  server.registerTool(
    'flutter_recent_network',
    description:
        'Fetch recent network calls the Flutter app made. Returns the last N '
        'entries the app pushed into TurboBridge.instance.network from its '
        'HTTP client interceptors (Dio/http/etc.). Each entry includes '
        'method, url, status, durationMs, and any captured error.',
    inputSchema: JsonSchema.object(
      properties: {
        'limit': JsonSchema.integer(
          description: 'Maximum number of recent calls to return (default 50).',
        ),
      },
    ),
    callback: (args, extra) async {
      final startedAtUtc = DateTime.now().toUtc();
      final limit = (args['limit'] as int?) ?? 50;
      try {
        final entries = await client.recentNetwork(limit: limit);
        return CallToolResult(
          content: [
            TextContent(
              text: encodeResponse(
                {'entries': entries, 'count': entries.length},
                startedAtUtc: startedAtUtc,
                completedAtUtc: DateTime.now().toUtc(),
              ),
            ),
          ],
        );
      } catch (e) {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text: encodeErrorResponse(
                'Recent network failed: $e',
                startedAtUtc: startedAtUtc,
                completedAtUtc: DateTime.now().toUtc(),
              ),
            ),
          ],
        );
      }
    },
  );
}
