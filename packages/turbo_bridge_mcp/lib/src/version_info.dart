const String turboBridgeMcpVersion = '0.3.0';

Map<String, dynamic> buildMcpCompatibilityInfo({
  required String bridgeVersion,
}) {
  final comparison = _compareVersions(bridgeVersion, turboBridgeMcpVersion);
  final status = comparison == null
      ? 'unknown'
      : comparison == 0
          ? 'up-to-date'
          : comparison > 0
              ? 'update-recommended'
              : 'bridge-update-recommended';

  final metadata = <String, dynamic>{
    'mcpServerVersion': turboBridgeMcpVersion,
    'mcpVersionStatus': status,
  };

  if (comparison == null) {
    return metadata;
  }

  if (comparison > 0) {
    metadata['updateHint'] =
        'Bridge reports version $bridgeVersion while this MCP server is '
        '$turboBridgeMcpVersion. Update turbo_bridge_mcp before continuing so '
        'the MCP tool contract stays aligned with the app bridge.';
  } else if (comparison < 0) {
    metadata['updateHint'] =
        'This MCP server is version $turboBridgeMcpVersion while the app bridge '
        'reports $bridgeVersion. Upgrade turbo_bridge in the app if you need '
        'the latest MCP-exposed capabilities.';
  }

  return metadata;
}

int? _compareVersions(String left, String right) {
  final leftParts = _parseVersion(left);
  final rightParts = _parseVersion(right);
  if (leftParts == null || rightParts == null) {
    return null;
  }

  final maxLength = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < maxLength; index++) {
    final leftValue = index < leftParts.length ? leftParts[index] : 0;
    final rightValue = index < rightParts.length ? rightParts[index] : 0;
    if (leftValue != rightValue) {
      return leftValue.compareTo(rightValue);
    }
  }

  return 0;
}

List<int>? _parseVersion(String value) {
  final normalized = value.split('+').first.split('-').first;
  final parts = normalized.split('.');
  if (parts.isEmpty) {
    return null;
  }

  final parsed = <int>[];
  for (final part in parts) {
    final number = int.tryParse(part);
    if (number == null) {
      return null;
    }
    parsed.add(number);
  }
  return parsed;
}
