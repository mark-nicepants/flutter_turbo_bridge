import 'dart:convert';

Map<String, dynamic> buildResponseMeta({
  required DateTime startedAtUtc,
  required DateTime completedAtUtc,
  Map<String, dynamic>? timing,
}) {
  final meta = <String, dynamic>{
    'startedAtUtc': startedAtUtc.toIso8601String(),
    'completedAtUtc': completedAtUtc.toIso8601String(),
  };
  if (timing != null && timing.isNotEmpty) {
    meta.addAll(timing);
  }
  return meta;
}

Map<String, dynamic> withResponseMeta(
  Map<String, dynamic> body, {
  required DateTime startedAtUtc,
  required DateTime completedAtUtc,
  Map<String, dynamic>? timing,
}) {
  return {
    ...body,
    '_meta': buildResponseMeta(
      startedAtUtc: startedAtUtc,
      completedAtUtc: completedAtUtc,
      timing: timing,
    ),
  };
}

String encodeResponse(
  Map<String, dynamic> body, {
  required DateTime startedAtUtc,
  required DateTime completedAtUtc,
  Map<String, dynamic>? timing,
}) {
  return const JsonEncoder.withIndent('  ').convert(
    withResponseMeta(
      body,
      startedAtUtc: startedAtUtc,
      completedAtUtc: completedAtUtc,
      timing: timing,
    ),
  );
}

String encodeErrorResponse(
  String message, {
  required DateTime startedAtUtc,
  required DateTime completedAtUtc,
}) {
  return encodeResponse(
    {'error': message},
    startedAtUtc: startedAtUtc,
    completedAtUtc: completedAtUtc,
  );
}
