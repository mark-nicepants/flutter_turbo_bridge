import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

import '../response_metadata.dart';

const int _defaultScreenshotDelayMs = 75;

/// Registers the `flutter_screenshot` tool.
void registerScreenshotTool(McpServer server, TurboBridgeClient client) {
  server.registerTool(
    'flutter_screenshot',
    description:
        'Capture a screenshot of the running Flutter app. Returns a PNG image. '
        'By default, waits 75ms before capture to reduce stale frames after taps and navigation.',
    inputSchema: JsonSchema.object(
      properties: {
        'pixelRatio': JsonSchema.number(
          description:
              'Pixel ratio for the screenshot (1.0 = logical pixels, 2.0 = retina)',
        ),
        'delayMs': JsonSchema.number(
          description:
              'Milliseconds to wait before capture. Defaults to 75ms to let the UI settle after interactions.',
        ),
      },
    ),
    callback: (args, extra) async {
      final startedAtUtc = DateTime.now().toUtc();
      final pixelRatio = (args['pixelRatio'] as num?)?.toDouble() ?? 1.0;
      final delayMs =
          (args['delayMs'] as num?)?.toInt() ?? _defaultScreenshotDelayMs;

      if (delayMs < 0) {
        final completedAtUtc = DateTime.now().toUtc();
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text: encodeErrorResponse(
                'Screenshot failed: delayMs must be >= 0',
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
              ),
            ),
          ],
        );
      }

      try {
        final result = await client.screenshot(
          pixelRatio: pixelRatio,
          delayMs: delayMs,
        );
        final completedAtUtc = DateTime.now().toUtc();
        return CallToolResult(
          content: [
            ImageContent(
              data: base64Encode(result.bytes),
              mimeType: 'image/png',
            ),
            TextContent(
              text: encodeResponse(
                {
                  'width': result.width,
                  'height': result.height,
                  'bytes': result.bytes.length,
                  'delayMs': delayMs,
                },
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
                timing: {
                  'captureTimeMs': result.captureTimeMs,
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
                'Screenshot failed: $e',
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
