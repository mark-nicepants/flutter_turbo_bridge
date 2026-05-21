/// App metadata returned by the bridge.
class AppInfo {
  final double screenWidth;
  final double screenHeight;
  final double pixelRatio;
  final String platform;
  final bool darkMode;
  final String? currentRoute;
  final String bridgeVersion;
  final String? locale;

  const AppInfo({
    required this.screenWidth,
    required this.screenHeight,
    required this.pixelRatio,
    required this.platform,
    required this.darkMode,
    this.currentRoute,
    required this.bridgeVersion,
    this.locale,
  });

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    return AppInfo(
      screenWidth: (json['screenWidth'] as num).toDouble(),
      screenHeight: (json['screenHeight'] as num).toDouble(),
      pixelRatio: (json['pixelRatio'] as num).toDouble(),
      platform: json['platform'] as String,
      darkMode: json['darkMode'] as bool,
      currentRoute: json['currentRoute'] as String?,
      bridgeVersion: json['bridgeVersion'] as String,
      locale: json['locale'] as String?,
    );
  }

  @override
  String toString() =>
      'AppInfo(${screenWidth}x$screenHeight @${pixelRatio}x, $platform)';
}
