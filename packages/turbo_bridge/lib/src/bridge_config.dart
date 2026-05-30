/// Configuration for the Turbo Bridge server.
class BridgeConfig {
  /// The port to listen on for HTTP and WebSocket connections.
  final int port;

  /// The host/interface to bind to.
  final String host;

  /// Whether to include timing headers in responses.
  final bool includeTimingHeaders;

  /// Maximum widget tree depth for `/tree` endpoint.
  final int defaultTreeDepth;

  /// Whether to start the in-browser DevTools UI on [devToolsPort].
  ///
  /// Off by default — never enable in a production build. DevTools opens an
  /// additional TCP port and exposes mutating endpoints (tap/swipe/input)
  /// without authentication beyond a same-origin header check.
  final bool enableDevTools;

  /// Port for the DevTools web UI. Ignored when [enableDevTools] is false.
  final int devToolsPort;

  /// Host/interface to bind the DevTools server to. Defaults to loopback;
  /// set to `0.0.0.0` to expose on LAN (logs a warning at startup).
  final String devToolsHost;

  /// Maximum number of recent JSON-API requests retained for the DevTools
  /// request log. The buffer is a ring; older entries are dropped.
  final int devToolsRequestLogSize;

  const BridgeConfig({
    this.port = 8888,
    this.host = '127.0.0.1',
    this.includeTimingHeaders = true,
    this.defaultTreeDepth = 10,
    this.enableDevTools = false,
    this.devToolsPort = 8889,
    this.devToolsHost = '127.0.0.1',
    this.devToolsRequestLogSize = 200,
  });
}
