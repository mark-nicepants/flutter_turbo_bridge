import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

/// Registers the `flutter://app/tree` resource.
void registerWidgetTreeResource(McpServer server, TurboBridgeClient client) {
  server.registerResource(
    'Widget Tree',
    'flutter://app/tree',
    (
      description: 'Current widget tree snapshot of the running Flutter app',
      mimeType: 'application/json'
    ),
    (uri, extra) async {
      try {
        final tree = await client.widgetTree(depth: 10);
        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: uri.toString(),
              text:
                  const JsonEncoder.withIndent('  ').convert(_nodeToJson(tree)),
              mimeType: 'application/json',
            ),
          ],
        );
      } catch (e) {
        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: uri.toString(),
              text: '{"error": "${e.toString().replaceAll('"', '\\"')}"}',
              mimeType: 'application/json',
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
