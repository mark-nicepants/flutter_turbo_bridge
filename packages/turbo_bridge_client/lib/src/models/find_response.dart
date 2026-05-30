/// Response from a server-side widget find operation.
class FindResponse {
  final bool found;
  final int count;
  final List<FoundWidgetResult> results;
  final int searchTimeMs;
  final int roundTripMs;

  const FindResponse({
    required this.found,
    required this.count,
    required this.results,
    required this.searchTimeMs,
    required this.roundTripMs,
  });

  factory FindResponse.fromJson(Map<String, dynamic> json, int roundTripMs) {
    return FindResponse(
      found: json['found'] as bool,
      count: json['count'] as int,
      results: (json['results'] as List<dynamic>?)
              ?.map(
                  (r) => FoundWidgetResult.fromJson(r as Map<String, dynamic>))
              .toList() ??
          const [],
      searchTimeMs: json['searchTimeMs'] as int? ?? 0,
      roundTripMs: roundTripMs,
    );
  }
}

/// A single widget match from a server-side find.
class FoundWidgetResult {
  final String type;
  final String? key;
  final String? text;
  final ({double x, double y})? center;
  final ({double x, double y, double w, double h})? bounds;
  final String? matchedBy;
  final double? score;
  final bool? isVisible;
  final bool? isCurrentRoute;
  final String? routeName;
  final String? tapTargetType;
  final String? tapTargetKey;

  const FoundWidgetResult({
    required this.type,
    this.key,
    this.text,
    this.center,
    this.bounds,
    this.matchedBy,
    this.score,
    this.isVisible,
    this.isCurrentRoute,
    this.routeName,
    this.tapTargetType,
    this.tapTargetKey,
  });

  factory FoundWidgetResult.fromJson(Map<String, dynamic> json) {
    final centerJson = json['center'] as Map<String, dynamic>?;
    final boundsJson = json['bounds'] as Map<String, dynamic>?;

    return FoundWidgetResult(
      type: json['type'] as String,
      key: json['key'] as String?,
      text: json['text'] as String?,
      center: centerJson != null
          ? (
              x: (centerJson['x'] as num).toDouble(),
              y: (centerJson['y'] as num).toDouble(),
            )
          : null,
      bounds: boundsJson != null
          ? (
              x: (boundsJson['x'] as num).toDouble(),
              y: (boundsJson['y'] as num).toDouble(),
              w: (boundsJson['w'] as num).toDouble(),
              h: (boundsJson['h'] as num).toDouble(),
            )
          : null,
      matchedBy: json['matchedBy'] as String?,
      score: (json['score'] as num?)?.toDouble(),
      isVisible: json['isVisible'] as bool?,
      isCurrentRoute: json['isCurrentRoute'] as bool?,
      routeName: json['routeName'] as String?,
      tapTargetType: json['tapTargetType'] as String?,
      tapTargetKey: json['tapTargetKey'] as String?,
    );
  }
}
