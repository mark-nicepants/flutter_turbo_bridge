import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

/// Registers the `flutter_inspect` prompt.
void registerInspectPrompt(McpServer server, TurboBridgeClient client) {
  server.registerPrompt(
    'flutter_inspect',
    description: 'Generate a comprehensive inspection of the running Flutter app. '
        'Captures a screenshot, widget tree, and app info, then provides '
        'analysis instructions.',
    argsSchema: {
      'focus': PromptArgumentDefinition(
        description: 'Optional area to focus the inspection on (e.g. "navigation", "layout", "accessibility")',
        required: false,
      ),
    },
    callback: (args, extra) async {
      final focus = args?['focus'] as String?;

      final messages = <PromptMessage>[
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(
            text: 'Please inspect the running Flutter app. '
                'Start by using these tools in order:\n\n'
                '1. Call `flutter_app_info` to understand the device/screen\n'
                '2. Call `flutter_screenshot` to see the current state\n'
                '3. Call `flutter_widget_tree` with depth=15 to understand the structure\n\n'
                'Then provide:\n'
                '- A summary of what the screen shows\n'
                '- The widget hierarchy and layout structure\n'
                '- Any issues you notice (overflow, accessibility, design)\n'
                '${focus != null ? '- Focus specifically on: $focus\n' : ''}'
                '- Suggested improvements',
          ),
        ),
      ];

      return GetPromptResult(
        description: 'Inspect Flutter app${focus != null ? ' (focus: $focus)' : ''}',
        messages: messages,
      );
    },
  );
}
