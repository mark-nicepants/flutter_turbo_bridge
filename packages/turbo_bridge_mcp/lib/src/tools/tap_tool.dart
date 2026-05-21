import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

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
      final x = (args['x'] as num).toDouble();
      final y = (args['y'] as num).toDouble();

      try {
        final result = await client.tap(x, y);
        return CallToolResult(
          content: [
            TextContent(
              text: jsonEncode({
                'success': result.success,
                'executionTimeMs': result.executionTimeMs,
                'roundTripMs': result.roundTripMs,
                if (result.error != null) 'error': result.error,
              }),
            ),
          ],
        );
      } catch (e) {
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Tap failed: $e')],
        );
      }
    },
  );
}
