import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:test/test.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

void main() {
  group('BridgeConnection', () {
    late BridgeConnection connection;

    group('isHealthy', () {
      test('returns true when server responds 200', () async {
        final mockClient = http_testing.MockClient((request) async {
          expect(request.url.path, '/health');
          return http.Response('{"status":"ok"}', 200);
        });

        connection = BridgeConnection.withClient(
          host: '127.0.0.1',
          port: 8888,
          client: mockClient,
        );

        expect(await connection.isHealthy(), isTrue);
      });

      test('returns false when server responds error', () async {
        final mockClient = http_testing.MockClient((request) async {
          return http.Response('error', 500);
        });

        connection = BridgeConnection.withClient(
          host: '127.0.0.1',
          port: 8888,
          client: mockClient,
        );

        expect(await connection.isHealthy(), isFalse);
      });

      test('returns false when connection fails', () async {
        final mockClient = http_testing.MockClient((request) async {
          throw Exception('Connection refused');
        });

        connection = BridgeConnection.withClient(
          host: '127.0.0.1',
          port: 8888,
          client: mockClient,
        );

        expect(await connection.isHealthy(), isFalse);
      });
    });

    group('screenshot', () {
      test('returns PNG bytes with timing metadata', () async {
        final pngBytes = Uint8List.fromList([137, 80, 78, 71, 0, 0, 0, 0]);

        final mockClient = http_testing.MockClient((request) async {
          expect(request.url.path, '/screenshot');
          expect(request.url.queryParameters['pixelRatio'], '2.0');
          return http.Response.bytes(
            pngBytes,
            200,
            headers: {
              'content-type': 'image/png',
              'x-capture-time-ms': '15',
              'x-image-width': '780',
              'x-image-height': '1688',
            },
          );
        });

        connection = BridgeConnection.withClient(
          host: '127.0.0.1',
          port: 8888,
          client: mockClient,
        );

        final result = await connection.screenshot(pixelRatio: 2.0);
        expect(result.bytes, pngBytes);
        expect(result.captureTimeMs, 15);
        expect(result.width, 780);
        expect(result.height, 1688);
        expect(result.roundTripMs, greaterThanOrEqualTo(0));
      });

      test('waits before requesting screenshot when delayMs is set', () async {
        final mockClient = http_testing.MockClient((request) async {
          return http.Response.bytes(
            Uint8List.fromList([137, 80, 78, 71]),
            200,
            headers: {
              'content-type': 'image/png',
              'x-capture-time-ms': '15',
            },
          );
        });

        connection = BridgeConnection.withClient(
          host: '127.0.0.1',
          port: 8888,
          client: mockClient,
        );

        final sw = Stopwatch()..start();
        await connection.screenshot(delayMs: 20);
        sw.stop();

        expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(15));
      });

      test('throws BridgeException on error response', () async {
        final mockClient = http_testing.MockClient((request) async {
          return http.Response('{"error":"No render tree"}', 503);
        });

        connection = BridgeConnection.withClient(
          host: '127.0.0.1',
          port: 8888,
          client: mockClient,
        );

        expect(
          () => connection.screenshot(),
          throwsA(isA<BridgeException>()),
        );
      });
    });

    group('widgetTree', () {
      test('returns parsed tree with timing', () async {
        final responseBody = jsonEncode({
          'captureTimeMs': 8,
          'rootWidget': {
            'type': 'MaterialApp',
            'children': [
              {
                'type': 'Text',
                'text': 'Hello',
                'rect': {'x': 0, 'y': 0, 'w': 100, 'h': 20}
              },
            ],
          },
        });

        final mockClient = http_testing.MockClient((request) async {
          expect(request.url.path, '/tree');
          expect(request.url.queryParameters['depth'], '5');
          return http.Response(responseBody, 200,
              headers: {'content-type': 'application/json'});
        });

        connection = BridgeConnection.withClient(
          host: '127.0.0.1',
          port: 8888,
          client: mockClient,
        );

        final result = await connection.widgetTree(depth: 5);
        expect(result.tree.type, 'MaterialApp');
        expect(result.tree.children, hasLength(1));
        expect(result.tree.children.first.text, 'Hello');
        expect(result.captureTimeMs, 8);
        expect(result.roundTripMs, greaterThanOrEqualTo(0));
      });

      test('passes focus query parameters', () async {
        final responseBody = jsonEncode({
          'captureTimeMs': 5,
          'rootWidget': {'type': 'Container'},
        });

        final mockClient = http_testing.MockClient((request) async {
          expect(request.url.path, '/tree');
          expect(request.url.queryParameters['x'], '120.5');
          expect(request.url.queryParameters['y'], '240.25');
          expect(request.url.queryParameters['ancestorLevels'], '3');
          return http.Response(responseBody, 200,
              headers: {'content-type': 'application/json'});
        });

        connection = BridgeConnection.withClient(
          host: '127.0.0.1',
          port: 8888,
          client: mockClient,
        );

        final result = await connection.widgetTree(
          depth: 4,
          x: 120.5,
          y: 240.25,
          ancestorLevels: 3,
        );
        expect(result.tree.type, 'Container');
      });

      test('rejects incomplete focus coordinates', () async {
        connection = BridgeConnection.withClient(
          host: '127.0.0.1',
          port: 8888,
          client: http_testing.MockClient((request) async {
            throw UnimplementedError();
          }),
        );

        expect(
          () => connection.widgetTree(x: 120.0),
          throwsArgumentError,
        );
      });
    });

    group('tap', () {
      test('sends coordinates and returns result', () async {
        final mockClient = http_testing.MockClient((request) async {
          expect(request.url.path, '/tap');
          expect(request.method, 'POST');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['x'], 195.0);
          expect(body['y'], 422.0);
          return http.Response(
            jsonEncode({'success': true, 'executionTimeMs': 3}),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        connection = BridgeConnection.withClient(
          host: '127.0.0.1',
          port: 8888,
          client: mockClient,
        );

        final result = await connection.tap(195.0, 422.0);
        expect(result.success, isTrue);
        expect(result.executionTimeMs, 3);
      });
    });

    group('appInfo', () {
      test('returns parsed app info', () async {
        final mockClient = http_testing.MockClient((request) async {
          expect(request.url.path, '/info');
          return http.Response(
            jsonEncode({
              'screenWidth': 390.0,
              'screenHeight': 844.0,
              'pixelRatio': 3.0,
              'platform': 'ios',
              'darkMode': false,
              'currentRoute': '/home',
              'bridgeVersion': '0.1.3',
              'locale': 'en_US',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        connection = BridgeConnection.withClient(
          host: '127.0.0.1',
          port: 8888,
          client: mockClient,
        );

        final info = await connection.appInfo();
        expect(info.screenWidth, 390.0);
        expect(info.screenHeight, 844.0);
        expect(info.pixelRatio, 3.0);
        expect(info.platform, 'ios');
        expect(info.darkMode, isFalse);
        expect(info.bridgeVersion, '0.1.3');
      });
    });
  });
}
