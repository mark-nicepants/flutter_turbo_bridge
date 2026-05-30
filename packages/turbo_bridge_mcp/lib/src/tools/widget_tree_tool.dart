import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

import '../response_metadata.dart';

/// Registers the `flutter_widget_tree` tool.
void registerWidgetTreeTool(McpServer server, TurboBridgeClient client) {
  server.registerTool(
    'flutter_widget_tree',
    description:
        'Get the current widget tree of the running Flutter app as JSON. '
        'Includes widget types, keys, text content, and layout bounds. '
        'Use depth=-1 for unlimited depth. '
        'Optional x/y coordinates focus the tree on a smaller local subtree.',
    inputSchema: JsonSchema.object(
      properties: {
        'depth': JsonSchema.integer(
          description: 'Max depth to traverse (-1 for unlimited, default 10)',
        ),
        'x': JsonSchema.number(
          description: 'Optional focus X coordinate in logical pixels',
        ),
        'y': JsonSchema.number(
          description: 'Optional focus Y coordinate in logical pixels',
        ),
        'ancestorLevels': JsonSchema.integer(
          description:
              'Ancestors to keep above the focused hit node (default 2)',
        ),
      },
    ),
    callback: (args, extra) async {
      final startedAtUtc = DateTime.now().toUtc();
      final depth = (args['depth'] as num?)?.toInt() ?? 10;
      final x = (args['x'] as num?)?.toDouble();
      final y = (args['y'] as num?)?.toDouble();
      final ancestorLevels = (args['ancestorLevels'] as num?)?.toInt() ?? 2;

      if ((x == null) != (y == null)) {
        final completedAtUtc = DateTime.now().toUtc();
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text: encodeErrorResponse(
                'Widget tree failed: x and y must be provided together',
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
              ),
            ),
          ],
        );
      }

      try {
        final result = await client.widgetTreeWithTiming(
          depth: depth,
          x: x,
          y: y,
          ancestorLevels: ancestorLevels,
        );
        final completedAtUtc = DateTime.now().toUtc();
        return CallToolResult(
          content: [
            TextContent(
              text: encodeResponse(
                _nodeToJson(result.tree),
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
                timing: {
                  'captureTimeMs': result.captureTimeMs,
                  'roundTripMs': result.roundTripMs,
                  if (x != null && y != null) 'focusPoint': {'x': x, 'y': y},
                  if (x != null && y != null) 'ancestorLevels': ancestorLevels,
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
                'Widget tree failed: $e',
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

Map<String, dynamic> _nodeToJson(WidgetNode node) {
  final json = <String, dynamic>{'type': node.type};
  if (node.key != null) json['key'] = node.key;
  if (node.text != null) json['text'] = node.text;
  if (node.rect != null) json['rect'] = node.rect;
  if (node.children.isNotEmpty) {
    json['children'] = node.children.map(_nodeToJson).toList();
  }
  return json;
}
