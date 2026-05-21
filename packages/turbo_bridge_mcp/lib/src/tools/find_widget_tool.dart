import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

/// Registers the `flutter_find_widget` tool.
void registerFindWidgetTool(McpServer server, TurboBridgeClient client) {
  server.registerTool(
    'flutter_find_widget',
    description: 'Find a widget in the Flutter app by text content, ValueKey, or widget type. '
        'Returns the widget\'s position and bounds so you can tap it. '
        'Provide exactly one of: text, key, or type.',
    inputSchema: JsonSchema.object(
      properties: {
        'text': JsonSchema.string(
          description: 'Find by text content (substring match)',
        ),
        'key': JsonSchema.string(
          description: 'Find by ValueKey string (exact match)',
        ),
        'type': JsonSchema.string(
          description: 'Find by widget type name (e.g. "ElevatedButton")',
        ),
      },
    ),
    callback: (args, extra) async {
      final text = args['text'] as String?;
      final key = args['key'] as String?;
      final type = args['type'] as String?;

      if (text == null && key == null && type == null) {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(text: 'Provide at least one of: text, key, or type'),
          ],
        );
      }

      try {
        final tree = await client.widgetTree(depth: -1);

        final List<WidgetNode> matches;
        if (key != null) {
          final found = tree.findByKey(key);
          matches = found != null ? [found] : [];
        } else if (text != null) {
          matches = tree.findByText(text);
        } else {
          matches = tree.findByType(type!);
        }

        if (matches.isEmpty) {
          return CallToolResult(
            content: [
              TextContent(
                text: jsonEncode({
                  'found': false,
                  'message': 'No widget found matching the criteria',
                }),
              ),
            ],
          );
        }

        final results = matches.take(10).map((node) {
          final center = node.center;
          return {
            'type': node.type,
            if (node.key != null) 'key': node.key,
            if (node.text != null) 'text': node.text,
            if (center != null) 'center': {'x': center.x, 'y': center.y},
            if (node.rect != null) 'bounds': node.rect,
          };
        }).toList();

        return CallToolResult(
          content: [
            TextContent(
              text: const JsonEncoder.withIndent('  ').convert({
                'found': true,
                'count': matches.length,
                'results': results,
              }),
            ),
          ],
        );
      } catch (e) {
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Find widget failed: $e')],
        );
      }
    },
  );
}
