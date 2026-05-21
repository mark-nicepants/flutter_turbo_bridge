import 'package:flutter/widgets.dart';

/// Result of a widget search.
class FindResult {
  final List<FoundWidget> matches;
  final int searchTimeMs;

  const FindResult({required this.matches, required this.searchTimeMs});

  Map<String, dynamic> toJson() => {
        'found': matches.isNotEmpty,
        'count': matches.length,
        'searchTimeMs': searchTimeMs,
        'results': matches.map((m) => m.toJson()).toList(),
      };
}

/// A widget match with its coordinates and metadata.
class FoundWidget {
  final String type;
  final String? key;
  final String? text;
  final double? x;
  final double? y;
  final double? width;
  final double? height;

  const FoundWidget({
    required this.type,
    this.key,
    this.text,
    this.x,
    this.y,
    this.width,
    this.height,
  });

  double? get centerX => x != null && width != null ? x! + width! / 2 : null;
  double? get centerY => y != null && height != null ? y! + height! / 2 : null;

  Map<String, dynamic> toJson() => {
        'type': type,
        if (key != null) 'key': key,
        if (text != null) 'text': text,
        if (x != null) 'bounds': {'x': x, 'y': y, 'w': width, 'h': height},
        if (centerX != null) 'center': {'x': centerX, 'y': centerY},
      };
}

/// Service for finding widgets in the element tree without serializing the
/// entire tree — much faster for targeted lookups.
class FindService {
  /// Find widgets matching the given criteria.
  ///
  /// Provide exactly one of [text], [key], or [type].
  /// Set [limit] to cap the number of results returned.
  FindResult find({
    String? text,
    String? key,
    String? type,
    int limit = 10,
  }) {
    final sw = Stopwatch()..start();
    final matches = <FoundWidget>[];

    final binding = WidgetsBinding.instance;
    final rootElement = binding.rootElement;
    if (rootElement == null) {
      sw.stop();
      return FindResult(matches: matches, searchTimeMs: sw.elapsedMilliseconds);
    }

    void visit(Element element) {
      if (matches.length >= limit) return;

      final widget = element.widget;
      bool matched = false;

      // Match by key
      if (key != null) {
        final widgetKey = widget.key;
        if (widgetKey is ValueKey && widgetKey.value.toString() == key) {
          matched = true;
        } else if (widgetKey != null && widgetKey.toString().contains(key)) {
          matched = true;
        }
      }

      // Match by text content
      if (text != null && !matched) {
        String? widgetText;
        if (widget is Text) {
          widgetText = widget.data ?? widget.textSpan?.toPlainText();
        } else if (widget is RichText) {
          widgetText = widget.text.toPlainText();
        } else if (widget is EditableText) {
          widgetText = widget.controller.text;
        }

        if (widgetText != null &&
            widgetText.toLowerCase().contains(text.toLowerCase())) {
          matched = true;
        }
      }

      // Match by type
      if (type != null && !matched) {
        final typeName = widget.runtimeType.toString();
        if (typeName.toLowerCase().contains(type.toLowerCase())) {
          matched = true;
        }
      }

      if (matched) {
        final renderObject = element.renderObject;
        double? x, y, w, h;

        if (renderObject is RenderBox && renderObject.hasSize) {
          try {
            final offset = renderObject.localToGlobal(Offset.zero);
            final size = renderObject.size;
            x = offset.dx;
            y = offset.dy;
            w = size.width;
            h = size.height;
          } catch (_) {}
        }

        // Extract text
        String? matchText;
        if (widget is Text) {
          matchText = widget.data ?? widget.textSpan?.toPlainText();
        } else if (widget is RichText) {
          matchText = widget.text.toPlainText();
        } else if (widget is EditableText) {
          matchText = widget.controller.text;
        }

        // Extract key
        String? keyStr;
        final widgetKey = widget.key;
        if (widgetKey is ValueKey) {
          keyStr = widgetKey.value.toString();
        } else if (widgetKey != null) {
          keyStr = widgetKey.toString();
        }

        matches.add(FoundWidget(
          type: widget.runtimeType.toString(),
          key: keyStr,
          text: matchText,
          x: x,
          y: y,
          width: w,
          height: h,
        ));
      }

      element.visitChildren(visit);
    }

    visit(rootElement);
    sw.stop();
    return FindResult(matches: matches, searchTimeMs: sw.elapsedMilliseconds);
  }
}
