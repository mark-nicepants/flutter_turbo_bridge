import 'package:mcp_dart/mcp_dart.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

import 'prompts/inspect_prompt.dart';
import 'resources/app_info_resource.dart';
import 'resources/widget_tree_resource.dart';
import 'tools/app_info_tool.dart';
import 'tools/enter_text_tool.dart';
import 'tools/find_widget_tool.dart';
import 'tools/screenshot_tool.dart';
import 'tools/scroll_tool.dart';
import 'tools/swipe_tool.dart';
import 'tools/tap_tool.dart';
import 'tools/widget_tree_tool.dart';
import 'version_info.dart';

/// Creates and configures the Turbo Bridge MCP server.
///
/// The server exposes Flutter app interaction capabilities as MCP tools,
/// resources, and prompts for consumption by LLM hosts.
McpServer createMcpServer({
  required TurboBridgeClient client,
}) {
  final server = McpServer(
    Implementation(
      name: 'flutter-turbo-bridge',
      version: turboBridgeMcpVersion,
    ),
    options: McpServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        resources: ServerCapabilitiesResources(),
        prompts: ServerCapabilitiesPrompts(),
      ),
    ),
  );

  // Register tools
  registerScreenshotTool(server, client);
  registerWidgetTreeTool(server, client);
  registerTapTool(server, client);
  registerSwipeTool(server, client);
  registerScrollTool(server, client);
  registerEnterTextTool(server, client);
  registerAppInfoTool(server, client);
  registerFindWidgetTool(server, client);

  // Register resources
  registerAppInfoResource(server, client);
  registerWidgetTreeResource(server, client);

  // Register prompts
  registerInspectPrompt(server, client);

  return server;
}
