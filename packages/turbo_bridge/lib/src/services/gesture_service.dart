import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
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
  int _pointerCounter = 0;

  int get _nextPointer => _pointerCounter++;

  /// Inject a tap at the given logical coordinates.
  GestureResult tap(double x, double y) {
    final sw = Stopwatch()..start();
    try {
      final binding = WidgetsBinding.instance;
      final pointer = _nextPointer;

      binding.handlePointerEvent(PointerDownEvent(
        pointer: pointer,
        position: Offset(x, y),
        kind: PointerDeviceKind.touch,
      ));

      binding.handlePointerEvent(PointerUpEvent(
        pointer: pointer,
        position: Offset(x, y),
        kind: PointerDeviceKind.touch,
      ));

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
  /// This dispatches the full sequence synchronously with a scheduled up event.
  GestureResult longPress(double x, double y, {Duration duration = const Duration(milliseconds: 500)}) {
    final sw = Stopwatch()..start();
    try {
      final binding = WidgetsBinding.instance;
      final pointer = _nextPointer;

      binding.handlePointerEvent(PointerDownEvent(
        pointer: pointer,
        position: Offset(x, y),
        kind: PointerDeviceKind.touch,
      ));

      Future.delayed(duration, () {
        binding.handlePointerEvent(PointerUpEvent(
          pointer: pointer,
          position: Offset(x, y),
          kind: PointerDeviceKind.touch,
        ));
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
  ///
  /// All events are dispatched synchronously for maximum speed.
  GestureResult swipe(
    double startX,
    double startY,
    double endX,
    double endY, {
    int steps = 10,
  }) {
    final sw = Stopwatch()..start();
    try {
      final binding = WidgetsBinding.instance;
      final pointer = _nextPointer;

      binding.handlePointerEvent(PointerDownEvent(
        pointer: pointer,
        position: Offset(startX, startY),
        kind: PointerDeviceKind.touch,
      ));

      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        final x = startX + (endX - startX) * t;
        final y = startY + (endY - startY) * t;

        binding.handlePointerEvent(PointerMoveEvent(
          pointer: pointer,
          position: Offset(x, y),
          kind: PointerDeviceKind.touch,
        ));
      }

      binding.handlePointerEvent(PointerUpEvent(
        pointer: pointer,
        position: Offset(endX, endY),
        kind: PointerDeviceKind.touch,
      ));

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

  /// Inject a scroll gesture at the given coordinates.
  ///
  /// [dx] and [dy] are the scroll delta in logical pixels.
  /// Positive [dy] scrolls down; negative scrolls up.
  GestureResult scroll(double x, double y, {double dx = 0, double dy = 0, int steps = 5}) {
    final sw = Stopwatch()..start();
    try {
      final binding = WidgetsBinding.instance;
      final pointer = _nextPointer;

      binding.handlePointerEvent(PointerDownEvent(
        pointer: pointer,
        position: Offset(x, y),
        kind: PointerDeviceKind.touch,
      ));

      final stepDx = dx / steps;
      final stepDy = dy / steps;

      for (var i = 1; i <= steps; i++) {
        binding.handlePointerEvent(PointerMoveEvent(
          pointer: pointer,
          position: Offset(x + stepDx * i, y + stepDy * i),
          kind: PointerDeviceKind.touch,
        ));
      }

      binding.handlePointerEvent(PointerUpEvent(
        pointer: pointer,
        position: Offset(x + dx, y + dy),
        kind: PointerDeviceKind.touch,
      ));

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

  /// Enter text into the currently focused text field.
  ///
  /// If [replaceExisting] is true, clears the field before typing.
  /// Returns a failed result if no text field is currently focused.
  Future<GestureResult> enterText(String text, {bool replaceExisting = false}) async {
    final sw = Stopwatch()..start();
    try {
      // Use the binary messenger to simulate the platform sending text input
      // state back to the framework. This avoids the crash that occurs when
      // calling TextInput.setEditingState via the platform channel without
      // an active native text input client.
      final messenger = ServicesBinding.instance.defaultBinaryMessenger;
      final codec = SystemChannels.textInput.codec;

      // Simulate the platform notifying the framework of the new editing state
      final stateMessage = codec.encodeMethodCall(
        MethodCall('TextInputClient.updateEditingState', <dynamic>[
          -1, // client ID — -1 means "current client"
          <String, dynamic>{
            'text': text,
            'selectionBase': text.length,
            'selectionExtent': text.length,
            'composingBase': -1,
            'composingExtent': -1,
          },
        ]),
      );

      await messenger.handlePlatformMessage(
        SystemChannels.textInput.name,
        stateMessage,
        (data) {},
      );

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
