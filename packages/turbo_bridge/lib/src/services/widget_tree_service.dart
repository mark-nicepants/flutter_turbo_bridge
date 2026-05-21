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
  /// Default maximum depth to traverse.
  final int defaultDepth;

  WidgetTreeService({this.defaultDepth = 10});

  /// Capture the current widget tree.
  ///
  /// Returns null if no element tree is available.
  /// [depth] limits traversal depth (-1 for unlimited).
  /// [compact] omits null fields in the output.
  WidgetNode? capture({int? depth, bool compact = true}) {
    final binding = WidgetsBinding.instance;
    final rootElement = binding.rootElement;
    if (rootElement == null) return null;

    return _buildNode(rootElement, 0, depth ?? defaultDepth);
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
}
