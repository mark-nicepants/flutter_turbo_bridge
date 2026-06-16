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
///   TurboBridge.start();
/// }
/// ```
library;

export 'interceptors/dio.dart' show TurboBridgeDioInterceptor;
export 'interceptors/http.dart' show TurboBridgeHttpInterceptor;
export 'src/bridge.dart';
export 'src/bridge_config.dart';
export 'src/devtools/log_sink.dart' show LogSink, LogEntry, LogLevel;
export 'src/devtools/navigation_log.dart' show NavigationLog, NavigationEntry;
export 'src/devtools/network_log.dart'
    show NetworkLog, NetworkCall, InFlightNetworkCall;
export 'src/devtools/turbo_navigation_observer.dart'
    show TurboNavigationObserver;
export 'src/services/app_info_service.dart';
export 'src/services/find_service.dart';
export 'src/services/gesture_service.dart';
export 'src/services/screenshot_service.dart';
export 'src/services/widget_tree_service.dart';
export 'src/version.dart' show turboBridgeVersion;
