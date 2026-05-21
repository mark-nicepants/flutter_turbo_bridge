import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_bridge/turbo_bridge.dart';

void main() {
  group('WidgetTreeService', () {
    late WidgetTreeService service;

    setUp(() {
      service = WidgetTreeService(defaultDepth: 50);
    });

    testWidgets('captures widget tree with correct types', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Hello World'),
          ),
        ),
      ));

      final tree = service.capture();
      expect(tree, isNotNull);
      expect(tree!.type, isNotEmpty);
      expect(tree.children, isNotEmpty);
    });

    testWidgets('captures text content at unlimited depth', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Text('Test Content'),
        ),
      ));

      final tree = service.capture(depth: -1);
      expect(tree, isNotNull);

      // Recursively search for any node with text content
      bool hasAnyText(WidgetNode node) {
        if (node.text != null && node.text!.isNotEmpty) return true;
        return node.children.any(hasAnyText);
      }

      expect(hasAnyText(tree!), isTrue);
    });

    testWidgets('captures widget keys at unlimited depth', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Container(
            key: const ValueKey('my_container'),
            child: const Text('Keyed'),
          ),
        ),
      ));

      final tree = service.capture(depth: -1);
      expect(tree, isNotNull);

      bool hasKey(WidgetNode node) {
        if (node.key == 'my_container') return true;
        return node.children.any(hasKey);
      }

      expect(hasKey(tree!), isTrue);
    });

    testWidgets('respects depth limit', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              children: [
                Text('Deep 1'),
                Text('Deep 2'),
              ],
            ),
          ),
        ),
      ));

      final shallow = service.capture(depth: 2);
      final deep = service.capture(depth: 50);

      expect(shallow, isNotNull);
      expect(deep, isNotNull);

      int countNodes(WidgetNode node) {
        return 1 +
            node.children.fold(0, (sum, child) => sum + countNodes(child));
      }

      // Deeper tree should have more nodes
      expect(countNodes(deep!), greaterThan(countNodes(shallow!)));
    });

    testWidgets('captures rect for rendered widgets', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: ValueKey('sized_box'),
              width: 100,
              height: 50,
              child: Placeholder(),
            ),
          ),
        ),
      ));

      final tree = service.capture(depth: -1);
      expect(tree, isNotNull);

      WidgetNode? findSizedBox(WidgetNode node) {
        if (node.key == 'sized_box') return node;
        for (final child in node.children) {
          final found = findSizedBox(child);
          if (found != null) return found;
        }
        return null;
      }

      final sizedBox = findSizedBox(tree!);
      expect(sizedBox, isNotNull);
      expect(sizedBox!.rect, isNotNull);
      expect(sizedBox.rect!['w'], 100.0);
      expect(sizedBox.rect!['h'], 50.0);
    });
  });

  group('GestureService', () {
    late GestureService service;

    setUp(() {
      service = GestureService();
    });

    testWidgets('tap returns success result', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SizedBox.expand()),
      ));

      // In test environment, handlePointerEvent works but gesture
      // recognition requires the test framework's pump cycle.
      // We just verify the service executes without error.
      final result = service.tap(100, 100);
      expect(result.success, isTrue);
      expect(result.executionTimeMs, greaterThanOrEqualTo(0));
      expect(result.executionTimeMs, lessThan(100));
    });

    testWidgets('tap with tester confirms gesture system works',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () => tapped = true,
            child: const Text('Tap me'),
          ),
        ),
      ));

      await tester.tap(find.text('Tap me'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('AppInfoService', () {
    late AppInfoService service;

    setUp(() {
      service = AppInfoService();
    });

    testWidgets('returns app info with expected fields', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));

      final info = service.getInfo();
      expect(info['screenWidth'], isA<double>());
      expect(info['screenHeight'], isA<double>());
      expect(info['pixelRatio'], isA<double>());
      expect(info['platform'], isA<String>());
      expect(info['darkMode'], isA<bool>());
      expect(info['bridgeVersion'], '0.1.0');
    });
  });

  group('BridgeConfig', () {
    test('has sensible defaults', () {
      const config = BridgeConfig();
      expect(config.port, 8888);
      expect(config.host, '127.0.0.1');
      expect(config.includeTimingHeaders, isTrue);
      expect(config.defaultTreeDepth, 10);
    });

    test('accepts custom values', () {
      const config = BridgeConfig(
        port: 9999,
        host: '0.0.0.0',
        includeTimingHeaders: false,
        defaultTreeDepth: 5,
      );
      expect(config.port, 9999);
      expect(config.host, '0.0.0.0');
      expect(config.includeTimingHeaders, isFalse);
      expect(config.defaultTreeDepth, 5);
    });
  });
}
