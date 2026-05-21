import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

/// Registers the `flutter://app/info` resource.
void registerAppInfoResource(McpServer server, TurboBridgeClient client) {
  server.registerResource(
    'App Info',
    'flutter://app/info',
    (description: 'Live metadata about the running Flutter app', mimeType: 'application/json'),
    (uri, extra) async {
      try {
        final info = await client.appInfo();
        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: uri.toString(),
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
