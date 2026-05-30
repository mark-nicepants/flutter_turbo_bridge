import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

import '../response_metadata.dart';

/// Registers the `flutter_swipe` tool.
void registerSwipeTool(McpServer server, TurboBridgeClient client) {
  server.registerTool(
    'flutter_swipe',
    description:
        'Perform a swipe gesture in the Flutter app from start to end coordinates. '
        'Useful for dismissing items, navigating carousels, or triggering pull-to-refresh.',
    inputSchema: JsonSchema.object(
      properties: {
        'startX': JsonSchema.number(description: 'Start X in logical pixels'),
        'startY': JsonSchema.number(description: 'Start Y in logical pixels'),
        'endX': JsonSchema.number(description: 'End X in logical pixels'),
        'endY': JsonSchema.number(description: 'End Y in logical pixels'),
        'steps': JsonSchema.number(
            description: 'Number of intermediate move events (default: 10)'),
      },
      required: ['startX', 'startY', 'endX', 'endY'],
    ),
    callback: (args, extra) async {
      final startedAtUtc = DateTime.now().toUtc();
      final startX = (args['startX'] as num).toDouble();
      final startY = (args['startY'] as num).toDouble();
      final endX = (args['endX'] as num).toDouble();
      final endY = (args['endY'] as num).toDouble();
      final steps = (args['steps'] as num?)?.toInt() ?? 10;

      try {
        final result =
            await client.swipe(startX, startY, endX, endY, steps: steps);
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
                'Swipe failed: $e',
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
