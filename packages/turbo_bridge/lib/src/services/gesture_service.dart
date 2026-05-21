import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Result of a gesture injection.
class GestureResult {
  final bool success;
  final int executionTimeMs;
  final String? error;

  const GestureResult({
    required this.success,
    required this.executionTimeMs,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'success': success,
        'executionTimeMs': executionTimeMs,
        if (error != null) 'error': error,
      };
}

/// Service for injecting pointer/gesture events into the Flutter app.
class GestureService {
  /// Inject a tap at the given logical coordinates.
  GestureResult tap(double x, double y) {
    final sw = Stopwatch()..start();
    try {
      final binding = WidgetsBinding.instance;

      // Create pointer down event
      final downEvent = PointerDownEvent(
        position: Offset(x, y),
        kind: PointerDeviceKind.touch,
      );

      // Create pointer up event
      final upEvent = PointerUpEvent(
        position: Offset(x, y),
        kind: PointerDeviceKind.touch,
      );

      binding.handlePointerEvent(downEvent);
      binding.handlePointerEvent(upEvent);

      sw.stop();
      return GestureResult(success: true, executionTimeMs: sw.elapsedMilliseconds);
    } catch (e) {
      sw.stop();
      return GestureResult(
        success: false,
        executionTimeMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  /// Inject a long press at the given coordinates.
  ///
  /// Note: This dispatches events synchronously. The actual long-press
  /// recognition depends on the gesture detector's timeout.
  GestureResult longPress(double x, double y, {Duration duration = const Duration(milliseconds: 500)}) {
    final sw = Stopwatch()..start();
    try {
      final binding = WidgetsBinding.instance;

      final downEvent = PointerDownEvent(
        position: Offset(x, y),
        kind: PointerDeviceKind.touch,
      );

      binding.handlePointerEvent(downEvent);

      // Schedule the up event after duration
      Future.delayed(duration, () {
        final upEvent = PointerUpEvent(
          position: Offset(x, y),
          kind: PointerDeviceKind.touch,
        );
        binding.handlePointerEvent(upEvent);
      });

      sw.stop();
      return GestureResult(success: true, executionTimeMs: sw.elapsedMilliseconds);
    } catch (e) {
      sw.stop();
      return GestureResult(
        success: false,
        executionTimeMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  /// Inject a swipe gesture from (startX, startY) to (endX, endY).
  GestureResult swipe(
    double startX,
    double startY,
    double endX,
    double endY, {
    int steps = 10,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    final sw = Stopwatch()..start();
    try {
      final binding = WidgetsBinding.instance;

      // Pointer down
      binding.handlePointerEvent(PointerDownEvent(
        position: Offset(startX, startY),
        kind: PointerDeviceKind.touch,
      ));

      // Intermediate move events
      final stepDuration = duration ~/ steps;
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        final x = startX + (endX - startX) * t;
        final y = startY + (endY - startY) * t;

        Future.delayed(stepDuration * i, () {
          binding.handlePointerEvent(PointerMoveEvent(
            position: Offset(x, y),
            kind: PointerDeviceKind.touch,
          ));

          if (i == steps) {
            binding.handlePointerEvent(PointerUpEvent(
              position: Offset(endX, endY),
              kind: PointerDeviceKind.touch,
            ));
          }
        });
      }

      sw.stop();
      return GestureResult(success: true, executionTimeMs: sw.elapsedMilliseconds);
    } catch (e) {
      sw.stop();
      return GestureResult(
        success: false,
        executionTimeMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }
}
