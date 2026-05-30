import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

import '../response_metadata.dart';

/// Registers the `flutter_tap` tool.
void registerTapTool(McpServer server, TurboBridgeClient client) {
  server.registerTool(
    'flutter_tap',
    description:
        'Tap at the given screen coordinates in the running Flutter app. '
        'Use flutter_find_widget first to locate tap targets.',
    inputSchema: JsonSchema.object(
      properties: {
        'x': JsonSchema.number(description: 'X coordinate in logical pixels'),
        'y': JsonSchema.number(description: 'Y coordinate in logical pixels'),
      },
      required: ['x', 'y'],
    ),
    callback: (args, extra) async {
      final startedAtUtc = DateTime.now().toUtc();
      final x = (args['x'] as num).toDouble();
      final y = (args['y'] as num).toDouble();

      try {
        final result = await client.tap(x, y);
        final completedAtUtc = DateTime.now().toUtc();
        return CallToolResult(
          content: [
            TextContent(
              text: encodeResponse(
                {
                  'success': result.success,
                  if (result.error != null) 'error': result.error,
                },
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
                timing: {
                  'executionTimeMs': result.executionTimeMs,
                  'roundTripMs': result.roundTripMs,
                },
              ),
            ),
          ],
        );
      } catch (e) {
        final completedAtUtc = DateTime.now().toUtc();
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text: encodeErrorResponse(
                'Tap failed: $e',
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
              ),
            ),
          ],
        );
      }
    },
  );
}
