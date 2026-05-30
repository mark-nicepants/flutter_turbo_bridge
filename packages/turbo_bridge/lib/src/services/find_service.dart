import 'dart:math' as math;

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
  final String? matchedBy;
  final double? score;
  final bool? isVisible;
  final bool? isCurrentRoute;
  final String? routeName;
  final String? tapTargetType;
  final String? tapTargetKey;

  const FoundWidget({
    required this.type,
    this.key,
    this.text,
    this.x,
    this.y,
    this.width,
    this.height,
    this.matchedBy,
    this.score,
    this.isVisible,
    this.isCurrentRoute,
    this.routeName,
    this.tapTargetType,
    this.tapTargetKey,
  });

  double? get centerX => x != null && width != null ? x! + width! / 2 : null;
  double? get centerY => y != null && height != null ? y! + height! / 2 : null;

  Map<String, dynamic> toJson() => {
        'type': type,
        if (key != null) 'key': key,
        if (text != null) 'text': text,
        if (x != null) 'bounds': {'x': x, 'y': y, 'w': width, 'h': height},
        if (centerX != null) 'center': {'x': centerX, 'y': centerY},
        if (matchedBy != null) 'matchedBy': matchedBy,
        if (score != null) 'score': score,
        if (isVisible != null) 'isVisible': isVisible,
        if (isCurrentRoute != null) 'isCurrentRoute': isCurrentRoute,
        if (routeName != null) 'routeName': routeName,
        if (tapTargetType != null) 'tapTargetType': tapTargetType,
        if (tapTargetKey != null) 'tapTargetKey': tapTargetKey,
      };
}

class _FindCandidate {
  final String type;
  final String? key;
  final String? text;
  final String matchedBy;
  final Rect? bounds;
  final bool isVisible;
  final bool isCurrentRoute;
  final String? routeName;
  final String? tapTargetType;
  final String? tapTargetKey;
  final bool isInteractive;
  final double score;

  const _FindCandidate({
    required this.type,
    this.key,
    this.text,
    required this.matchedBy,
    this.bounds,
    required this.isVisible,
    required this.isCurrentRoute,
    this.routeName,
    this.tapTargetType,
    this.tapTargetKey,
    required this.isInteractive,
    required this.score,
  });

  FoundWidget toFoundWidget() => FoundWidget(
        type: type,
        key: key,
        text: text,
        x: bounds?.left,
        y: bounds?.top,
        width: bounds?.width,
        height: bounds?.height,
        matchedBy: matchedBy,
        score: score,
        isVisible: isVisible,
        isCurrentRoute: isCurrentRoute,
        routeName: routeName,
        tapTargetType: tapTargetType,
        tapTargetKey: tapTargetKey,
      );
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
    bool visibleOnly = true,
    bool currentRouteOnly = false,
    bool interactiveOnly = false,
    double? nearX,
    double? nearY,
  }) {
    final sw = Stopwatch()..start();
    final matches = <FoundWidget>[];

    final binding = WidgetsBinding.instance;
    final rootElement = binding.rootElement;
    if (rootElement == null) {
      sw.stop();
      return FindResult(matches: matches, searchTimeMs: sw.elapsedMilliseconds);
    }

    final viewportRect = _viewportRect(binding);
    final candidates = <_FindCandidate>[];

    void visit(Element element, {required bool isOffstage}) {
      final widget = element.widget;
      final nextIsOffstage =
          isOffstage || (widget is Offstage && widget.offstage);
      String? matchedBy;

      // Match by key
      if (key != null) {
        final widgetKey = widget.key;
        if (widgetKey is ValueKey && widgetKey.value.toString() == key) {
          matchedBy = 'key-exact';
        } else if (widgetKey != null && widgetKey.toString().contains(key)) {
          matchedBy = 'key-substring';
        }
      }

      // Match by text content
      if (text != null && matchedBy == null) {
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
          matchedBy = widgetText.toLowerCase() == text.toLowerCase()
              ? 'text-exact'
              : 'text-substring';
        }
      }

      // Match by type
      if (type != null && matchedBy == null) {
        final typeName = widget.runtimeType.toString();
        if (typeName.toLowerCase().contains(type.toLowerCase())) {
          matchedBy = typeName.toLowerCase() == type.toLowerCase()
              ? 'type-exact'
              : 'type-substring';
        }
      }

      if (matchedBy != null) {
        final route = _routeFor(element);
        final routeName = _routeName(route);
        final routeOffstage = route is ModalRoute<dynamic> && route.offstage;
        final isCurrentRoute = route?.isCurrent ?? false;

        final matchBounds = _boundsFor(element);
        final tapTarget = _resolveTapTarget(element);
        final tapBounds = _boundsFor(tapTarget ?? element);
        final bounds = tapBounds ?? matchBounds;
        final isInteractive = tapTarget != null;
        final isVisible = !nextIsOffstage &&
            !routeOffstage &&
            bounds != null &&
            bounds.width > 0 &&
            bounds.height > 0 &&
            _intersectsViewport(bounds, viewportRect);

        candidates.add(
          _FindCandidate(
            type: widget.runtimeType.toString(),
            key: _keyFor(widget),
            text: _textFor(widget),
            matchedBy: matchedBy,
            bounds: bounds,
            isVisible: isVisible,
            isCurrentRoute: isCurrentRoute,
            routeName: routeName,
            tapTargetType: tapTarget?.widget.runtimeType.toString(),
            tapTargetKey: tapTarget != null ? _keyFor(tapTarget.widget) : null,
            isInteractive: isInteractive,
            score: _scoreCandidate(
              matchedBy: matchedBy,
              bounds: bounds,
              viewportRect: viewportRect,
              isVisible: isVisible,
              isCurrentRoute: isCurrentRoute,
              isInteractive: isInteractive,
              nearX: nearX,
              nearY: nearY,
            ),
          ),
        );
      }

      element
          .visitChildren((child) => visit(child, isOffstage: nextIsOffstage));
    }

    visit(rootElement, isOffstage: false);

    final selected = _selectCandidates(
      candidates,
      visibleOnly: visibleOnly,
      currentRouteOnly: currentRouteOnly,
      interactiveOnly: interactiveOnly,
    );

    selected.sort((a, b) => b.score.compareTo(a.score));
    matches.addAll(
        selected.take(limit).map((candidate) => candidate.toFoundWidget()));

    sw.stop();
    return FindResult(matches: matches, searchTimeMs: sw.elapsedMilliseconds);
  }

  List<_FindCandidate> _selectCandidates(
    List<_FindCandidate> candidates, {
    required bool visibleOnly,
    required bool currentRouteOnly,
    required bool interactiveOnly,
  }) {
    List<_FindCandidate> apply({
      required bool requireVisible,
      required bool requireCurrentRoute,
      required bool requireInteractive,
    }) {
      return candidates.where((candidate) {
        if (requireVisible && !candidate.isVisible) return false;
        if (requireCurrentRoute && !candidate.isCurrentRoute) return false;
        if (requireInteractive && !candidate.isInteractive) return false;
        return true;
      }).toList();
    }

    final strict = apply(
      requireVisible: visibleOnly,
      requireCurrentRoute: currentRouteOnly,
      requireInteractive: interactiveOnly,
    );
    if (strict.isNotEmpty) return strict;

    if (currentRouteOnly) {
      final relaxedRoute = apply(
        requireVisible: visibleOnly,
        requireCurrentRoute: false,
        requireInteractive: interactiveOnly,
      );
      if (relaxedRoute.isNotEmpty) return relaxedRoute;
    }

    if (visibleOnly) {
      final relaxedVisibility = apply(
        requireVisible: false,
        requireCurrentRoute: false,
        requireInteractive: interactiveOnly,
      );
      if (relaxedVisibility.isNotEmpty) return relaxedVisibility;
    }

    if (interactiveOnly) {
      final relaxedInteractive = apply(
        requireVisible: false,
        requireCurrentRoute: false,
        requireInteractive: false,
      );
      if (relaxedInteractive.isNotEmpty) return relaxedInteractive;
    }

    return candidates;
  }

  Rect _viewportRect(WidgetsBinding binding) {
    final view = binding.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return Offset.zero & size;
  }

  Route<dynamic>? _routeFor(Element element) {
    try {
      return ModalRoute.of(element);
    } catch (_) {
      return null;
    }
  }

  String? _routeName(Route<dynamic>? route) {
    if (route == null) return null;
    return route.settings.name ?? route.runtimeType.toString();
  }

  Rect? _boundsFor(Element element) {
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

  bool _intersectsViewport(Rect bounds, Rect viewportRect) {
    return bounds.overlaps(viewportRect);
  }

  Element? _resolveTapTarget(Element element) {
    if (_isInteractiveWidget(element.widget)) {
      return element;
    }

    Element? tapTarget;
    element.visitAncestorElements((ancestor) {
      if (_isInteractiveWidget(ancestor.widget)) {
        tapTarget = ancestor;
        return false;
      }
      return true;
    });
    return tapTarget;
  }

  bool _isInteractiveWidget(Widget widget) {
    final typeName = widget.runtimeType.toString();
    return typeName == 'InkWell' ||
        typeName == 'GestureDetector' ||
        typeName == 'Listener' ||
        typeName.endsWith('Button') ||
        typeName == 'ListTile' ||
        typeName == 'Tab' ||
        typeName == 'NavigationDestination' ||
        typeName == 'NavigationRailDestination' ||
        typeName == 'InkResponse' ||
        typeName == '_InkResponseStateWidget';
  }

  String? _textFor(Widget widget) {
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText();
    }
    if (widget is RichText) {
      return widget.text.toPlainText();
    }
    if (widget is EditableText) {
      return widget.controller.text;
    }
    return null;
  }

  String? _keyFor(Widget widget) {
    final widgetKey = widget.key;
    if (widgetKey is ValueKey) {
      return widgetKey.value.toString();
    }
    return widgetKey?.toString();
  }

  double _scoreCandidate({
    required String matchedBy,
    required Rect? bounds,
    required Rect viewportRect,
    required bool isVisible,
    required bool isCurrentRoute,
    required bool isInteractive,
    required double? nearX,
    required double? nearY,
  }) {
    var score = 0.0;

    if (isVisible) score += 1000;
    if (isCurrentRoute) score += 300;
    if (isInteractive) score += 120;

    if (matchedBy.endsWith('exact')) {
      score += 80;
    } else {
      score += 30;
    }

    if (bounds != null) {
      final viewportArea = viewportRect.width * viewportRect.height;
      final areaScore = math.min(bounds.width * bounds.height, viewportArea);
      score += (areaScore / viewportArea) * 30;

      final targetX = nearX ?? viewportRect.center.dx;
      final targetY = nearY ?? viewportRect.center.dy;
      final dx = bounds.center.dx - targetX;
      final dy = bounds.center.dy - targetY;
      final distance = math.sqrt((dx * dx) + (dy * dy));
      final maxDistance = math.sqrt(
        (viewportRect.width * viewportRect.width) +
            (viewportRect.height * viewportRect.height),
      );
      score += (1 - math.min(distance / maxDistance, 1)) * 25;
    }

    return score;
  }
}
