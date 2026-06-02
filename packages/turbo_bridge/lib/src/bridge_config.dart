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

  /// Whether to expose the DevTools data endpoints (`devtools/*`) and the
  /// `events` SSE stream on the bridge port, and to instrument requests into
  /// the request log.
  ///
  /// Off by default — never enable in a production build. The DevTools web UI
  /// itself is no longer served by the app; it runs on the developer's
  /// machine (e.g. `turbo_bridge_devtools` / the MCP server) and talks to
  /// these endpoints over the (loopback / adb-forwarded) bridge port.
  final bool enableDevTools;

  /// Maximum number of recent JSON-API requests retained for the DevTools
  /// request log. The buffer is a ring; older entries are dropped.
  final int devToolsRequestLogSize;

  const BridgeConfig({
    this.port = 8888,
    this.host = '127.0.0.1',
    this.includeTimingHeaders = true,
    this.defaultTreeDepth = 10,
    this.enableDevTools = false,
    this.devToolsRequestLogSize = 200,
  });
}
