import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:test/test.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

void main() {
  group('TurboBridgeClient', () {
    late TurboBridgeClient client;
    late http_testing.MockClient mockHttpClient;

    setUp(() {
      mockHttpClient = http_testing.MockClient((request) async {
        final path = request.url.path;
        return switch (path) {
          '/health' => http.Response('{"status":"ok"}', 200),
          '/screenshot' => http.Response.bytes(
              Uint8List.fromList([137, 80, 78, 71]),
              200,
              headers: {
                'content-type': 'image/png',
                'x-capture-time-ms': '10',
                'x-image-width': '390',
                'x-image-height': '844',
              },
            ),
          '/tree' => http.Response(
              jsonEncode({
                'captureTimeMs': 5,
                'rootWidget': {
                  'type': 'MaterialApp',
                  'children': [
                    {
                      'type': 'Text',
                      'key': 'counter_text',
                      'text': '0',
                      'rect': {'x': 170, 'y': 400, 'w': 50, 'h': 30},
                    },
                    {
                      'type': 'FloatingActionButton',
                      'key': 'increment_button',
                      'rect': {'x': 320, 'y': 750, 'w': 56, 'h': 56},
                      'children': [
                        {'type': 'Icon'},
                      ],
                    },
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          '/tap' => http.Response(
              jsonEncode({'success': true, 'executionTimeMs': 2}),
              200,
              headers: {'content-type': 'application/json'},
            ),
          '/info' => http.Response(
              jsonEncode({
                'screenWidth': 390.0,
                'screenHeight': 844.0,
                'pixelRatio': 3.0,
                'platform': 'macos',
                'darkMode': false,
                'bridgeVersion': '0.1.0',
                'locale': 'en_US',
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          _ => http.Response('Not found', 404),
        };
      });

      client = TurboBridgeClient.withConnections(
        bridge: BridgeConnection.withClient(
          host: '127.0.0.1',
          port: 8888,
          client: mockHttpClient,
        ),
      );
    });

    test('isConnected returns true when healthy', () async {
      expect(await client.isConnected(), isTrue);
    });

    test('screenshot returns PNG bytes', () async {
      final result = await client.screenshot();
      expect(result.bytes, hasLength(4));
      expect(result.bytes[0], 137); // PNG magic byte
      expect(result.captureTimeMs, 10);
    });

    test('widgetTree returns parsed tree', () async {
      final tree = await client.widgetTree();
      expect(tree.type, 'MaterialApp');
      expect(tree.children, hasLength(2));
    });

    test('widgetTreeWithTiming includes timing', () async {
      final result = await client.widgetTreeWithTiming();
      expect(result.captureTimeMs, 5);
      expect(result.roundTripMs, greaterThanOrEqualTo(0));
      expect(result.tree.type, 'MaterialApp');
    });

    test('tap sends coordinates', () async {
      final result = await client.tap(195, 422);
      expect(result.success, isTrue);
      expect(result.executionTimeMs, 2);
    });

    test('tapByKey finds widget and taps center', () async {
      final result = await client.tapByKey('increment_button');
      expect(result, isNotNull);
      expect(result!.success, isTrue);
    });

    test('tapByKey returns null for missing key', () async {
      final result = await client.tapByKey('nonexistent');
      expect(result, isNull);
    });

    test('tapByText finds widget and taps center', () async {
      final result = await client.tapByText('0');
      expect(result, isNotNull);
      expect(result!.success, isTrue);
    });

    test('tapByText returns null for missing text', () async {
      final result = await client.tapByText('nonexistent text');
      expect(result, isNull);
    });

    test('appInfo returns metadata', () async {
      final info = await client.appInfo();
      expect(info.screenWidth, 390.0);
      expect(info.platform, 'macos');
    });

    test('evaluate throws when VM service not connected', () async {
      expect(
        () => client.evaluate('1+1'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
