/// Result of a tap injection.
class TapResult {
  final bool success;
  final int executionTimeMs;
  final int roundTripMs;
  final String? error;

  const TapResult({
    required this.success,
    required this.executionTimeMs,
    required this.roundTripMs,
    this.error,
  });

  factory TapResult.fromJson(Map<String, dynamic> json, int roundTripMs) {
    return TapResult(
      success: json['success'] as bool,
      executionTimeMs: json['executionTimeMs'] as int,
      roundTripMs: roundTripMs,
      error: json['error'] as String?,
    );
  }

  @override
  String toString() =>
      'TapResult(success=$success, exec=${executionTimeMs}ms, roundTrip=${roundTripMs}ms)';
}
