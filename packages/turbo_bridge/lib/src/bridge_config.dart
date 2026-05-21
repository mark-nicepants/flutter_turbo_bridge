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

  const BridgeConfig({
    this.port = 8888,
    this.host = '127.0.0.1',
    this.includeTimingHeaders = true,
    this.defaultTreeDepth = 10,
  });
}
