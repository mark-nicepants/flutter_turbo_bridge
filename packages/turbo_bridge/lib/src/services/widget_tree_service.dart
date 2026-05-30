import 'package:flutter/widgets.dart';

/// A compact representation of a widget tree node for AI consumption.
class WidgetNode {
  final String type;
  final String? key;
  final Map<String, double>? rect;
  final String? text;
  final List<WidgetNode> children;

  const WidgetNode({
    required this.type,
    this.key,
    this.rect,
    this.text,
    this.children = const [],
  });

  Map<String, dynamic> toJson({bool compact = true}) {
    final map = <String, dynamic>{
      'type': type,
    };
    if (!compact || key != null) map['key'] = key;
    if (!compact || rect != null) map['rect'] = rect;
    if (!compact || text != null) map['text'] = text;
    if (children.isNotEmpty) {
      map['children'] =
          children.map((c) => c.toJson(compact: compact)).toList();
    }
    return map;
  }
}

/// Service for extracting the widget tree as a compact JSON structure.
class WidgetTreeService {
  static const Set<String> _frameworkShellTypes = {
    'View',
    'RawView',
    '_RawViewInternal',
    '_ViewScope',
  };

  /// Default maximum depth to traverse.
  final int defaultDepth;

  WidgetTreeService({this.defaultDepth = 10});

  /// Capture the current widget tree.
  ///
  /// Returns null if no element tree is available.
  /// [depth] limits traversal depth (-1 for unlimited).
  /// [compact] omits null fields in the output.
  /// [focusX] and [focusY] optionally crop the tree around a screen coordinate.
  /// [ancestorLevels] keeps local context above the deepest hit node.
  WidgetNode? capture({
    int? depth,
    bool compact = true,
    double? focusX,
    double? focusY,
    int ancestorLevels = 2,
  }) {
    final binding = WidgetsBinding.instance;
    final rootElement = binding.rootElement;
    if (rootElement == null) return null;

    final normalizedRoot = _stripFrameworkShell(rootElement);
    final captureRoot = focusX != null && focusY != null
        ? _resolveFocusedRoot(
            normalizedRoot,
            focusX: focusX,
            focusY: focusY,
            ancestorLevels: ancestorLevels,
          )
        : normalizedRoot;

    return _buildNode(captureRoot, 0, depth ?? defaultDepth);
  }

  Element _stripFrameworkShell(Element element) {
    var current = element;
    while (
        _frameworkShellTypes.contains(current.widget.runtimeType.toString())) {
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

  Element _resolveFocusedRoot(
    Element root, {
    required double focusX,
    required double focusY,
    required int ancestorLevels,
  }) {
    final hitPath = _findDeepestHitPath(root, Offset(focusX, focusY));
    if (hitPath == null || hitPath.isEmpty) {
      return root;
    }

    final ancestorOffset = ancestorLevels < 0 ? 0 : ancestorLevels;
    var targetIndex = (hitPath.length - 1 - ancestorOffset).clamp(
      0,
      hitPath.length - 1,
    );
    while (targetIndex > 0 && _childCountOf(hitPath[targetIndex]) <= 1) {
      targetIndex -= 1;
    }
    return hitPath[targetIndex];
  }

  int _childCountOf(Element element) {
    var count = 0;
    element.visitChildren((_) {
      count += 1;
    });
    return count;
  }

  List<Element>? _findDeepestHitPath(Element element, Offset point) {
    List<Element>? deepestChildPath;

    element.visitChildren((child) {
      final childPath = _findDeepestHitPath(child, point);
      if (childPath != null &&
          (deepestChildPath == null ||
              childPath.length > deepestChildPath!.length)) {
        deepestChildPath = childPath;
      }
    });

    if (deepestChildPath != null) {
      return [element, ...deepestChildPath!];
    }

    final rect = _rectFor(element);
    if (rect != null && rect.contains(point)) {
      return [element];
    }

    return null;
  }

  Rect? _rectFor(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }

    try {
      final offset = renderObject.localToGlobal(Offset.zero);
      return offset & renderObject.size;
    } catch (_) {
      return null;
    }
  }

  WidgetNode _buildNode(Element element, int currentDepth, int maxDepth) {
    final widget = element.widget;
    final renderObject = element.renderObject;

    // Extract key
    String? keyStr;
    final key = widget.key;
    if (key is ValueKey) {
      keyStr = key.value.toString();
    } else if (key != null) {
      keyStr = key.toString();
    }

    // Extract bounds
    Map<String, double>? rect;
    if (renderObject is RenderBox && renderObject.hasSize) {
      try {
        final offset = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;
        rect = {
          'x': offset.dx,
          'y': offset.dy,
          'w': size.width,
          'h': size.height,
        };
      } catch (_) {
        // RenderObject not laid out yet
      }
    }

    // Extract text content
    String? text;
    if (widget is Text) {
      text = widget.data ?? widget.textSpan?.toPlainText();
    } else if (widget is RichText) {
      text = widget.text.toPlainText();
    }

    // Build children
    final children = <WidgetNode>[];
    if (maxDepth == -1 || currentDepth < maxDepth) {
      element.visitChildren((child) {
        children.add(_buildNode(child, currentDepth + 1, maxDepth));
      });
    }

    return WidgetNode(
      type: widget.runtimeType.toString(),
      key: keyStr,
      rect: rect,
      text: text,
      children: children,
    );
  }

  /// Returns the chain of widgets that contain the given screen point,
  /// from the root down to the most-specific hit. Used by the DevTools
  /// "inspect mode" — click on a screenshot to identify a widget.
  ///
  /// Each entry includes `type`, optional `key`, `rect`, optional `text`,
  /// and optional `creationLocation` ({ file, line, column }) when widget
  /// creation tracking is enabled (`--track-widget-creation`, default in
  /// debug builds).
  List<Map<String, dynamic>> pickAt(double x, double y) {
    final binding = WidgetsBinding.instance;
    final rootElement = binding.rootElement;
    if (rootElement == null) return const [];

    final normalizedRoot = _stripFrameworkShell(rootElement);
    final hit = _findDeepestHitPath(normalizedRoot, Offset(x, y));
    if (hit == null) return const [];

    return hit.map(_elementSummary).toList(growable: false);
  }

  Map<String, dynamic> _elementSummary(Element element) {
    final widget = element.widget;
    String? keyStr;
    final key = widget.key;
    if (key is ValueKey) {
      keyStr = key.value.toString();
    } else if (key != null) {
      keyStr = key.toString();
    }

    Map<String, double>? rect;
    final renderObject = element.renderObject;
    if (renderObject is RenderBox && renderObject.hasSize) {
      try {
        final offset = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;
        rect = {
          'x': offset.dx,
          'y': offset.dy,
          'w': size.width,
          'h': size.height,
        };
      } catch (_) {}
    }

    String? text;
    if (widget is Text) {
      text = widget.data ?? widget.textSpan?.toPlainText();
    } else if (widget is RichText) {
      text = widget.text.toPlainText();
    }

    return <String, dynamic>{
      'type': widget.runtimeType.toString(),
      if (keyStr != null) 'key': keyStr,
      if (rect != null) 'rect': rect,
      if (text != null) 'text': text,
    };
  }
}
