import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

import '../response_metadata.dart';
import '../version_info.dart';

/// Registers the `flutter_app_info` tool.
void registerAppInfoTool(McpServer server, TurboBridgeClient client) {
  server.registerTool(
    'flutter_app_info',
    description: 'Get metadata about the running Flutter app: screen size, pixel ratio, '
        'platform, dark mode status, and bridge version.',
    inputSchema: JsonSchema.object(properties: {}),
    callback: (args, extra) async {
      final startedAtUtc = DateTime.now().toUtc();
      try {
        final info = await client.appInfo();
        final completedAtUtc = DateTime.now().toUtc();
        return CallToolResult(
          content: [
            TextContent(
              text: encodeResponse(
                {
                  'screenWidth': info.screenWidth,
                  'screenHeight': info.screenHeight,
                  'pixelRatio': info.pixelRatio,
                  'platform': info.platform,
                  'darkMode': info.darkMode,
                  'bridgeVersion': info.bridgeVersion,
                  ...buildMcpCompatibilityInfo(bridgeVersion: info.bridgeVersion),
                  if (info.currentRoute != null) 'currentRoute': info.currentRoute,
                  if (info.locale != null) 'locale': info.locale,
                },
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
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
                'App info failed: $e',
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
