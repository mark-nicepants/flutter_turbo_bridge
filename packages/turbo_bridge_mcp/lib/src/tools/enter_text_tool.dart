import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

import '../response_metadata.dart';

/// Registers the `flutter_enter_text` tool.
void registerEnterTextTool(McpServer server, TurboBridgeClient client) {
  server.registerTool(
    'flutter_enter_text',
    description: 'Enter text into the currently focused text field in the Flutter app. '
        'Tap a text field first using flutter_tap or flutter_find_widget to focus it, '
        'then use this tool to type text.',
    inputSchema: JsonSchema.object(
      properties: {
        'text': JsonSchema.string(description: 'The text to enter'),
        'replace': JsonSchema.boolean(description: 'If true, replaces existing text. If false (default), appends.'),
      },
      required: ['text'],
    ),
    callback: (args, extra) async {
      final startedAtUtc = DateTime.now().toUtc();
      final text = args['text'] as String;
      final replace = args['replace'] as bool? ?? false;

      try {
        final result = await client.enterText(text, replace: replace);
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
                'Enter text failed: $e',
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
