import 'dart:typed_data';

/// Result of a screenshot capture operation.
class ScreenshotResult {
  /// The raw PNG bytes.
  final Uint8List bytes;

  /// Time taken to capture on the app side (ms).
  final int captureTimeMs;

  /// Image width in pixels.
  final int? width;

  /// Image height in pixels.
  final int? height;

  /// Total round-trip time including network (ms).
  final int roundTripMs;

  const ScreenshotResult({
    required this.bytes,
    required this.captureTimeMs,
    this.width,
    this.height,
    required this.roundTripMs,
  });

  @override
  String toString() =>
      'ScreenshotResult(${bytes.length} bytes, capture=${captureTimeMs}ms, roundTrip=${roundTripMs}ms)';
}
