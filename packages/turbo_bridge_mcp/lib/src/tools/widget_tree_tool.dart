import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

/// Registers the `flutter_widget_tree` tool.
void registerWidgetTreeTool(McpServer server, TurboBridgeClient client) {
  server.registerTool(
    'flutter_widget_tree',
    description: 'Get the current widget tree of the running Flutter app as JSON. '
        'Includes widget types, keys, text content, and layout bounds. '
        'Use depth=-1 for unlimited depth.',
    inputSchema: JsonSchema.object(
      properties: {
        'depth': JsonSchema.integer(
          description: 'Max depth to traverse (-1 for unlimited, default 10)',
        ),
      },
    ),
    callback: (args, extra) async {
      final depth = (args['depth'] as num?)?.toInt() ?? 10;

      try {
        final result = await client.widgetTreeWithTiming(depth: depth);
        return CallToolResult(
          content: [
            TextContent(
              text: const JsonEncoder.withIndent('  ').convert(_nodeToJson(result.tree)),
            ),
          ],
        );
      } catch (e) {
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Widget tree failed: $e')],
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
