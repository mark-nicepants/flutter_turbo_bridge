import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Service for providing app metadata.
class AppInfoService {
  /// Get current app information.
  Map<String, dynamic> getInfo() {
    final binding = WidgetsBinding.instance;
    final window = binding.platformDispatcher.views.first;

    final size = window.physicalSize / window.devicePixelRatio;

    String? currentRoute;
    // Try to get current route from navigator
    try {
      final element = binding.rootElement;
      if (element != null) {
        element.visitChildElements((child) {
          if (child is StatefulElement && child.state is NavigatorState) {
            // Navigator found — could extract route, but keeping simple for MVP
          }
        });
      }
    } catch (_) {}

    return {
      'screenWidth': size.width,
      'screenHeight': size.height,
      'pixelRatio': window.devicePixelRatio,
      'platform': _platformName(),
      'darkMode':
          binding.platformDispatcher.platformBrightness == ui.Brightness.dark,
      'currentRoute': currentRoute,
      'bridgeVersion': '0.1.1',
      'locale': binding.platformDispatcher.locale.toString(),
    };
  }

  String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
