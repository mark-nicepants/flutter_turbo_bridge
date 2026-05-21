/// Flutter Turbo Bridge Client — High-speed client for AI-Flutter interaction.
///
/// Connects to both the in-app Turbo Bridge server and the Dart VM Service
/// for maximum speed and capability.
///
/// ```dart
/// import 'package:turbo_bridge_client/turbo_bridge_client.dart';
///
/// final client = TurboBridgeClient(host: '127.0.0.1', port: 8888);
/// await client.connect();
/// final screenshot = await client.screenshot();
/// final tree = await client.widgetTree();
/// await client.tap(195, 422);
/// await client.dispose();
/// ```
library turbo_bridge_client;

export 'src/bridge_connection.dart';
export 'src/client.dart';
export 'src/models/app_info.dart';
export 'src/models/find_response.dart';
export 'src/models/screenshot_result.dart';
export 'src/models/tap_result.dart';
export 'src/models/widget_node.dart';
export 'src/vm_service_connection.dart';
