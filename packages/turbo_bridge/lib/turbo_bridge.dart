/// Flutter Turbo Bridge — In-app companion server for ultra-fast AI interaction.
///
/// Add `TurboBridge` to your Flutter app to expose HTTP/WebSocket endpoints
/// for screenshots, widget tree inspection, and gesture injection.
///
/// ```dart
/// import 'package:turbo_bridge/turbo_bridge.dart';
///
/// void main() {
///   runApp(const MyApp());
///   TurboBridge.instance.start();
/// }
/// ```
library turbo_bridge;

export 'src/bridge.dart';
export 'src/bridge_config.dart';
export 'src/services/app_info_service.dart';
export 'src/services/gesture_service.dart';
export 'src/services/screenshot_service.dart';
export 'src/services/widget_tree_service.dart';
