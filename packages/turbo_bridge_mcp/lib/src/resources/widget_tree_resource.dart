import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

import '../response_metadata.dart';

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
      final startedAtUtc = DateTime.now().toUtc();
      try {
        final result = await client.widgetTreeWithTiming(depth: 10);
        final completedAtUtc = DateTime.now().toUtc();
        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: uri.toString(),
              text: encodeResponse(
                _nodeToJson(result.tree),
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
                timing: {
                  'captureTimeMs': result.captureTimeMs,
                  'roundTripMs': result.roundTripMs,
                },
              ),
              mimeType: 'application/json',
            ),
          ],
        );
      } catch (e) {
        final completedAtUtc = DateTime.now().toUtc();
        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: uri.toString(),
              text: encodeErrorResponse(
                e.toString(),
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
              ),
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
