import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Service for capturing screenshots of the running Flutter app.
///
/// Uses [RenderRepaintBoundary.toImage] for fast in-process capture.
class ScreenshotService {
  static const Set<String> _frameworkShellTypes = {
    'View',
    'RawView',
    '_RawViewInternal',
    '_ViewScope',
  };

  /// Capture a screenshot of the app's current frame.
  ///
  /// Returns PNG-encoded bytes. The [pixelRatio] controls resolution
  /// (1.0 = logical pixels, higher = more detail).
  ///
  /// Returns null if no render tree is available yet.
  Future<Uint8List?> capture({double pixelRatio = 1.0}) async {
    final binding = WidgetsBinding.instance;
    final surfaceSize = _surfaceSizeFor(binding);
    if (surfaceSize == null) return null;

    final renderView = _findRenderView(binding);
    if (renderView != null) {
      if (renderView.debugNeedsPaint) {
        await binding.endOfFrame;
      }

      final rootLayer = renderView.debugLayer;
      if (rootLayer is OffsetLayer) {
        final image = await rootLayer.toImage(
          renderView.paintBounds,
          pixelRatio: pixelRatio,
        );
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return byteData?.buffer.asUint8List();
      }
    }

    var renderBoundary = _findCaptureBoundary(
      binding,
      surfaceSize: surfaceSize,
      requirePainted: true,
    );
    renderBoundary ??= _findCaptureBoundary(binding, surfaceSize: surfaceSize);
    if (renderBoundary == null) return null;

    if (renderBoundary.debugNeedsPaint) {
      await binding.endOfFrame;
      renderBoundary = _findCaptureBoundary(
            binding,
            surfaceSize: surfaceSize,
            requirePainted: true,
          ) ??
          renderBoundary;
    }

    if (renderBoundary.debugNeedsPaint) {
      return null;
    }

    final image = await renderBoundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    return byteData?.buffer.asUint8List();
  }

  /// Get the dimensions of the current render surface.
  ui.Size? get surfaceSize => _surfaceSizeFor(WidgetsBinding.instance);

  ui.Size? _surfaceSizeFor(WidgetsBinding binding) {
    final renderViews = binding.renderViews;
    if (renderViews.isEmpty) return null;
    return renderViews.first.paintBounds.size;
  }

  RenderView? _findRenderView(WidgetsBinding binding) {
    final renderViews = binding.renderViews;
    if (renderViews.isEmpty) return null;
    return renderViews.first;
  }

  RenderRepaintBoundary? _findCaptureBoundary(
    WidgetsBinding binding, {
    required ui.Size surfaceSize,
    bool requirePainted = false,
  }) {
    final rootElement = binding.rootElement;
    if (rootElement == null) return null;

    RenderRepaintBoundary? fullscreenBoundary;
    RenderRepaintBoundary? largestBoundary;
    var largestArea = 0.0;

    void visitor(Element element, {bool isOffstage = false}) {
      final widget = element.widget;
      final nextIsOffstage = isOffstage || (widget is Offstage && widget.offstage);
      if (nextIsOffstage) {
        return;
      }

      final renderObject = element.renderObject;
      if (renderObject is RenderRepaintBoundary && renderObject.hasSize) {
        if (requirePainted && renderObject.debugNeedsPaint) {
          element.visitChildren((child) {
            visitor(child, isOffstage: nextIsOffstage);
          });
          return;
        }

        final size = renderObject.size;
        final area = size.width * size.height;
        if (_matchesSurface(size, surfaceSize)) {
          fullscreenBoundary = renderObject;
        }
        if (area > largestArea) {
          largestArea = area;
          largestBoundary = renderObject;
        }
      }

      element.visitChildren((child) {
        visitor(child, isOffstage: nextIsOffstage);
      });
    }

    visitor(_stripFrameworkShell(rootElement));
    return fullscreenBoundary ?? largestBoundary;
  }

  bool _matchesSurface(Size boundarySize, ui.Size surfaceSize) {
    const tolerance = 1.0;
    return (boundarySize.width - surfaceSize.width).abs() <= tolerance &&
        (boundarySize.height - surfaceSize.height).abs() <= tolerance;
  }

  Element _stripFrameworkShell(Element element) {
    var current = element;
    while (_frameworkShellTypes.contains(current.widget.runtimeType.toString())) {
      final child = _singleChildOf(current);
      if (child == null) {
        break;
      }
      current = child;
    }
    return current;
  }

  Element? _singleChildOf(Element element) {
    Element? onlyChild;
    var childCount = 0;
    element.visitChildren((child) {
      childCount += 1;
      if (childCount == 1) {
        onlyChild = child;
      }
    });
    return childCount == 1 ? onlyChild : null;
  }
}
