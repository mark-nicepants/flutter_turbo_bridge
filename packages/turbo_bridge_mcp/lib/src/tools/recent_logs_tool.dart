import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

import '../response_metadata.dart';

/// Registers the `flutter_recent_logs` tool: returns app-pushed log lines
/// that the running app has fed into TurboBridge's LogSink. Useful when
/// an LLM needs to inspect what the app has been doing recently.
void registerRecentLogsTool(McpServer server, TurboBridgeClient client) {
  server.registerTool(
    'flutter_recent_logs',
    description:
        'Fetch recent app-emitted log lines from the running Flutter app. '
        'Returns the last N entries that the app pushed into '
        'TurboBridge.instance.logs. Each entry has timestamp, level, '
        'optional category, message, and optional error/stackTrace.',
    inputSchema: JsonSchema.object(
      properties: {
        'limit': JsonSchema.integer(
          description: 'Maximum number of recent entries to return (default 50).',
        ),
        'level': JsonSchema.string(
          description:
              'Minimum severity to include: trace, debug, info, warn, error.',
        ),
      },
    ),
    callback: (args, extra) async {
      final startedAtUtc = DateTime.now().toUtc();
      final limit = (args['limit'] as int?) ?? 50;
      final level = args['level'] as String?;
      try {
        final entries = await client.recentLogs(limit: limit, level: level);
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
                'Recent logs failed: $e',
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
