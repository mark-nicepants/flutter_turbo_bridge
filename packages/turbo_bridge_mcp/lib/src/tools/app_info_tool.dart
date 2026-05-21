import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

/// Registers the `flutter_app_info` tool.
void registerAppInfoTool(McpServer server, TurboBridgeClient client) {
  server.registerTool(
    'flutter_app_info',
    description: 'Get metadata about the running Flutter app: screen size, pixel ratio, '
        'platform, dark mode status, and bridge version.',
    inputSchema: JsonSchema.object(properties: {}),
    callback: (args, extra) async {
      try {
        final info = await client.appInfo();
        return CallToolResult(
          content: [
            TextContent(
              text: const JsonEncoder.withIndent('  ').convert({
                'screenWidth': info.screenWidth,
                'screenHeight': info.screenHeight,
                'pixelRatio': info.pixelRatio,
                'platform': info.platform,
                'darkMode': info.darkMode,
                'bridgeVersion': info.bridgeVersion,
                if (info.currentRoute != null) 'currentRoute': info.currentRoute,
                if (info.locale != null) 'locale': info.locale,
              }),
            ),
          ],
        );
      } catch (e) {
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'App info failed: $e')],
        );
      }
    },
  );
}
