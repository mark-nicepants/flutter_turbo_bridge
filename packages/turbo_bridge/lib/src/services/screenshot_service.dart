import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Service for capturing screenshots of the running Flutter app.
///
/// Uses [RenderRepaintBoundary.toImage] for fast in-process capture.
class ScreenshotService {
  /// Capture a screenshot of the app's current frame.
  ///
  /// Returns PNG-encoded bytes. The [pixelRatio] controls resolution
  /// (1.0 = logical pixels, higher = more detail).
  ///
  /// Returns null if no render tree is available yet.
  Future<Uint8List?> capture({double pixelRatio = 1.0}) async {
    final binding = WidgetsBinding.instance;
    final renderView = _findRenderRepaintBoundary(binding);
    if (renderView == null) return null;

    final image = await renderView.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    return byteData?.buffer.asUint8List();
  }

  /// Get the dimensions of the current render surface.
  ui.Size? get surfaceSize {
    final binding = WidgetsBinding.instance;
    final renderView = binding.rootElement?.renderObject;
    if (renderView == null) return null;
    return renderView.paintBounds.size;
  }

  RenderRepaintBoundary? _findRenderRepaintBoundary(WidgetsBinding binding) {
    final rootElement = binding.rootElement;
    if (rootElement == null) return null;

    RenderRepaintBoundary? boundary;
    void visitor(Element element) {
      if (boundary != null) return;
      final renderObject = element.renderObject;
      if (renderObject is RenderRepaintBoundary) {
        boundary = renderObject;
        return;
      }
      element.visitChildren(visitor);
    }

    visitor(rootElement);
    return boundary;
  }
}
