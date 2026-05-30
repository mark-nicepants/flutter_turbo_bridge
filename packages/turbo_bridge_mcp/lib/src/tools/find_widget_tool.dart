import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

import '../response_metadata.dart';

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
        'visibleOnly': JsonSchema.boolean(
          description: 'Prefer only matches that intersect the visible viewport. Defaults to true.',
        ),
        'currentRouteOnly': JsonSchema.boolean(
          description: 'Restrict matches to the current top route when possible. Defaults to false.',
        ),
        'interactiveOnly': JsonSchema.boolean(
          description: 'Restrict matches to widgets with an interactive tap target. Defaults to false.',
        ),
        'nearX': JsonSchema.number(
          description: 'Optional X coordinate to bias match ranking toward a region.',
        ),
        'nearY': JsonSchema.number(
          description: 'Optional Y coordinate to bias match ranking toward a region.',
        ),
        'limit': JsonSchema.number(
          description: 'Maximum number of matches to return. Defaults to 10.',
        ),
      },
    ),
    callback: (args, extra) async {
      final startedAtUtc = DateTime.now().toUtc();
      final text = args['text'] as String?;
      final key = args['key'] as String?;
      final type = args['type'] as String?;
      final visibleOnly = args['visibleOnly'] as bool? ?? true;
      final currentRouteOnly = args['currentRouteOnly'] as bool? ?? false;
      final interactiveOnly = args['interactiveOnly'] as bool? ?? false;
      final nearX = (args['nearX'] as num?)?.toDouble();
      final nearY = (args['nearY'] as num?)?.toDouble();
      final limit = (args['limit'] as num?)?.toInt() ?? 10;

      if (text == null && key == null && type == null) {
        final completedAtUtc = DateTime.now().toUtc();
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text: encodeErrorResponse(
                'Provide at least one of: text, key, or type',
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
              ),
            ),
          ],
        );
      }

      try {
        final response = await client.find(
          text: text,
          key: key,
          type: type,
          visibleOnly: visibleOnly,
          currentRouteOnly: currentRouteOnly,
          interactiveOnly: interactiveOnly,
          nearX: nearX,
          nearY: nearY,
          limit: limit,
        );
        final completedAtUtc = DateTime.now().toUtc();

        if (!response.found) {
          return CallToolResult(
            content: [
              TextContent(
                text: encodeResponse(
                  {
                    'found': false,
                    'count': 0,
                    'results': const [],
                    'message': 'No widget found matching the criteria',
                  },
                  startedAtUtc: startedAtUtc,
                  completedAtUtc: completedAtUtc,
                  timing: {
                    'searchTimeMs': response.searchTimeMs,
                    'roundTripMs': response.roundTripMs,
                  },
                ),
              ),
            ],
          );
        }

        final results = response.results.map((node) {
          return {
            'type': node.type,
            if (node.key != null) 'key': node.key,
            if (node.text != null) 'text': node.text,
            if (node.center != null) 'center': {'x': node.center!.x, 'y': node.center!.y},
            if (node.bounds != null)
              'bounds': {
                'x': node.bounds!.x,
                'y': node.bounds!.y,
                'w': node.bounds!.w,
                'h': node.bounds!.h,
              },
            if (node.matchedBy != null) 'matchedBy': node.matchedBy,
            if (node.score != null) 'score': node.score,
            if (node.isVisible != null) 'isVisible': node.isVisible,
            if (node.isCurrentRoute != null) 'isCurrentRoute': node.isCurrentRoute,
            if (node.routeName != null) 'routeName': node.routeName,
            if (node.tapTargetType != null) 'tapTargetType': node.tapTargetType,
            if (node.tapTargetKey != null) 'tapTargetKey': node.tapTargetKey,
          };
        }).toList();

        return CallToolResult(
          content: [
            TextContent(
              text: encodeResponse(
                {
                  'found': true,
                  'count': response.count,
                  'results': results,
                },
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
                timing: {
                  'searchTimeMs': response.searchTimeMs,
                  'roundTripMs': response.roundTripMs,
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
                'Find widget failed: $e',
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
