import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

/// Registers the `flutter_screenshot` tool.
void registerScreenshotTool(McpServer server, TurboBridgeClient client) {
  server.registerTool(
    'flutter_screenshot',
    description: 'Capture a screenshot of the running Flutter app. Returns a PNG image.',
    inputSchema: JsonSchema.object(
      properties: {
        'pixelRatio': JsonSchema.number(
          description: 'Pixel ratio for the screenshot (1.0 = logical pixels, 2.0 = retina)',
        ),
      },
    ),
    callback: (args, extra) async {
      final pixelRatio = (args['pixelRatio'] as num?)?.toDouble() ?? 1.0;

      try {
        final result = await client.screenshot(pixelRatio: pixelRatio);
        return CallToolResult(
          content: [
            ImageContent(
              data: base64Encode(result.bytes),
              mimeType: 'image/png',
            ),
            TextContent(
              text: 'Screenshot captured: '
                  '${result.width}x${result.height}px, '
                  '${result.bytes.length} bytes, '
                  'capture=${result.captureTimeMs}ms, '
                  'roundTrip=${result.roundTripMs}ms',
            ),
          ],
        );
      } catch (e) {
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Screenshot failed: $e')],
        );
      }
    },
  );
}
