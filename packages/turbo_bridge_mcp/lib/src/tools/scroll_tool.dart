import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

/// Registers the `flutter_scroll` tool.
void registerScrollTool(McpServer server, TurboBridgeClient client) {
  server.registerTool(
    'flutter_scroll',
    description: 'Scroll at a position in the Flutter app. '
        'Positive dy scrolls content up (finger moves up). '
        'Negative dy scrolls content down.',
    inputSchema: JsonSchema.object(
      properties: {
        'x': JsonSchema.number(description: 'X coordinate of the scroll area center'),
        'y': JsonSchema.number(description: 'Y coordinate of the scroll area center'),
        'dy': JsonSchema.number(
            description: 'Vertical scroll distance in logical pixels (positive = up, negative = down)'),
        'dx': JsonSchema.number(description: 'Horizontal scroll distance (default: 0)'),
      },
      required: ['x', 'y', 'dy'],
    ),
    callback: (args, extra) async {
      final x = (args['x'] as num).toDouble();
      final y = (args['y'] as num).toDouble();
      final dy = (args['dy'] as num).toDouble();
      final dx = (args['dx'] as num?)?.toDouble() ?? 0;

      try {
        final result = await client.scroll(x, y, dx: dx, dy: dy);
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
          content: [TextContent(text: 'Scroll failed: $e')],
        );
      }
    },
  );
}
