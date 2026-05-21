import 'package:test/test.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

void main() {
  group('WidgetNode', () {
    final sampleTree = WidgetNode(
      type: 'MaterialApp',
      children: [
        WidgetNode(
          type: 'Scaffold',
          children: [
            WidgetNode(
              type: 'Column',
              children: [
                WidgetNode(
                  type: 'Text',
                  key: 'counter_text',
                  text: '42',
                  rect: {'x': 100, 'y': 200, 'w': 50, 'h': 30},
                ),
                WidgetNode(
                  type: 'ElevatedButton',
                  key: 'submit_button',
                  rect: {'x': 80, 'y': 300, 'w': 100, 'h': 48},
                  children: [
                    WidgetNode(type: 'Text', text: 'Submit'),
                  ],
                ),
                WidgetNode(
                  type: 'Text',
                  text: 'Login here',
                  rect: {'x': 50, 'y': 400, 'w': 200, 'h': 20},
                ),
              ],
            ),
          ],
        ),
      ],
    );

    test('findByKey returns matching node', () {
      final node = sampleTree.findByKey('counter_text');
      expect(node, isNotNull);
      expect(node!.type, 'Text');
      expect(node.text, '42');
    });

    test('findByKey returns null for missing key', () {
      final node = sampleTree.findByKey('nonexistent');
      expect(node, isNull);
    });

    test('findByText returns all matching nodes', () {
      final nodes = sampleTree.findByText('Submit');
      expect(nodes, hasLength(1));
      expect(nodes.first.type, 'Text');
    });

    test('findByText with partial match', () {
      final nodes = sampleTree.findByText('Login');
      expect(nodes, hasLength(1));
      expect(nodes.first.text, 'Login here');
    });

    test('findByType returns all matching nodes', () {
      final nodes = sampleTree.findByType('Text');
      expect(nodes, hasLength(3));
    });

    test('center calculates correctly', () {
      final node = sampleTree.findByKey('submit_button')!;
      final center = node.center;
      expect(center, isNotNull);
      expect(center!.x, 130.0); // 80 + 100/2
      expect(center.y, 324.0); // 300 + 48/2
    });

    test('center is null when no rect', () {
      final node = WidgetNode(type: 'Container');
      expect(node.center, isNull);
    });

    test('findAll with custom predicate', () {
      final nodes = sampleTree.findAll((n) => n.rect != null);
      expect(nodes, hasLength(3));
    });

    group('fromJson', () {
      test('parses minimal node', () {
        final node = WidgetNode.fromJson({'type': 'Container'});
        expect(node.type, 'Container');
        expect(node.key, isNull);
        expect(node.rect, isNull);
        expect(node.text, isNull);
        expect(node.children, isEmpty);
      });

      test('parses full node with children', () {
        final node = WidgetNode.fromJson({
          'type': 'Text',
          'key': 'my_key',
          'text': 'Hello',
          'rect': {'x': 10.0, 'y': 20.0, 'w': 100.0, 'h': 50.0},
          'children': [
            {'type': 'RichText', 'text': 'World'}
          ],
        });
        expect(node.type, 'Text');
        expect(node.key, 'my_key');
        expect(node.text, 'Hello');
        expect(node.rect!['x'], 10.0);
        expect(node.children, hasLength(1));
        expect(node.children.first.text, 'World');
      });

      test('handles integer rect values', () {
        final node = WidgetNode.fromJson({
          'type': 'Box',
          'rect': {'x': 10, 'y': 20, 'w': 100, 'h': 50},
        });
        expect(node.rect!['x'], 10.0);
        expect(node.rect!['w'], 100.0);
      });
    });
  });
}
