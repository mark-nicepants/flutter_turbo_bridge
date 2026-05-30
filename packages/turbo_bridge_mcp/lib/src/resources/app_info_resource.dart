import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

import '../response_metadata.dart';

/// Registers the `flutter://app/info` resource.
void registerAppInfoResource(McpServer server, TurboBridgeClient client) {
  server.registerResource(
    'App Info',
    'flutter://app/info',
    (description: 'Live metadata about the running Flutter app', mimeType: 'application/json'),
    (uri, extra) async {
      final startedAtUtc = DateTime.now().toUtc();
      try {
        final info = await client.appInfo();
        final completedAtUtc = DateTime.now().toUtc();
        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: uri.toString(),
              text: encodeResponse(
                {
                  'screenWidth': info.screenWidth,
                  'screenHeight': info.screenHeight,
                  'pixelRatio': info.pixelRatio,
                  'platform': info.platform,
                  'darkMode': info.darkMode,
                  'bridgeVersion': info.bridgeVersion,
                  if (info.currentRoute != null) 'currentRoute': info.currentRoute,
                  if (info.locale != null) 'locale': info.locale,
                },
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
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
