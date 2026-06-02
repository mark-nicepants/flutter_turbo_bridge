import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';
import 'package:turbo_bridge_mcp/turbo_bridge_mcp.dart';

class MockTurboBridgeClient extends Mock implements TurboBridgeClient {}

/// Creates an in-memory client/server pair connected via IOStreamTransport.
Future<McpClient> createTestClient(McpServer server) async {
  final serverToClient = StreamController<List<int>>();
  final clientToServer = StreamController<List<int>>();

  final serverTransport = IOStreamTransport(
    stream: clientToServer.stream,
    sink: serverToClient.sink,
  );
  final clientTransport = IOStreamTransport(
    stream: serverToClient.stream,
    sink: clientToServer.sink,
  );

  final client = McpClient(
    Implementation(name: 'test-client', version: '0.1.0'),
  );

  await server.connect(serverTransport);
  await client.connect(clientTransport);

  return client;
}

void main() {
  late MockTurboBridgeClient mockClient;
  late McpServer server;
  late McpClient mcpClient;

  setUp(() async {
    mockClient = MockTurboBridgeClient();
    server = createMcpServer(client: mockClient);
    mcpClient = await createTestClient(server);
  });

  tearDown(() async {
    await mcpClient.close();
    await server.close();
  });

  group('createMcpServer', () {
    test('registers all tools', () async {
      final tools = await mcpClient.listTools();
      final names = tools.tools.map((t) => t.name).toSet();
      expect(
          names,
          containsAll([
            'flutter_screenshot',
            'flutter_widget_tree',
            'flutter_tap',
            'flutter_app_info',
            'flutter_find_widget',
          ]));
    });

    test('registers all resources', () async {
      final resources = await mcpClient.listResources();
      final uris = resources.resources.map((r) => r.uri).toSet();
      expect(
          uris,
          containsAll([
            'flutter://app/info',
            'flutter://app/tree',
          ]));
    });

    test('registers all prompts', () async {
      final prompts = await mcpClient.listPrompts();
      final names = prompts.prompts.map((p) => p.name).toSet();
      expect(names, contains('flutter_inspect'));
    });
  });

  group('screenshot tool', () {
    test('returns image content on success', () async {
      final pngBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      when(() => mockClient.screenshot(
            pixelRatio: any(named: 'pixelRatio'),
            delayMs: any(named: 'delayMs'),
          )).thenAnswer((_) async => ScreenshotResult(
            bytes: pngBytes,
            captureTimeMs: 5,
            width: 400,
            height: 800,
            roundTripMs: 10,
          ));

      final result = await mcpClient.callTool(
        CallToolRequest(name: 'flutter_screenshot', arguments: {}),
      );

      expect(result.isError, isNot(true));
      expect(result.content.length, 2);
      expect(result.content[0], isA<ImageContent>());
      final image = result.content[0] as ImageContent;
      expect(image.mimeType, 'image/png');
      expect(image.data, base64Encode(pngBytes));
      final metadata = jsonDecode((result.content[1] as TextContent).text)
          as Map<String, dynamic>;
      expect(metadata['width'], 400);
      expect(metadata['_meta']['captureTimeMs'], 5);
      expect(metadata['_meta']['roundTripMs'], 10);
      expect(metadata['_meta']['startedAtUtc'], isA<String>());
      expect(metadata['_meta']['completedAtUtc'], isA<String>());
    });

    test('passes pixelRatio parameter and default delay', () async {
      when(() => mockClient.screenshot(pixelRatio: 2.0, delayMs: 75))
          .thenAnswer((_) async => ScreenshotResult(
                bytes: Uint8List(0),
                captureTimeMs: 5,
                width: 800,
                height: 1600,
                roundTripMs: 10,
              ));

      await mcpClient.callTool(
        CallToolRequest(
          name: 'flutter_screenshot',
          arguments: {'pixelRatio': 2.0},
        ),
      );

      verify(() => mockClient.screenshot(pixelRatio: 2.0, delayMs: 75))
          .called(1);
    });

    test('passes explicit delay parameter', () async {
      when(() => mockClient.screenshot(pixelRatio: 1.0, delayMs: 120))
          .thenAnswer((_) async => ScreenshotResult(
                bytes: Uint8List(0),
                captureTimeMs: 5,
                width: 400,
                height: 800,
                roundTripMs: 10,
              ));

      await mcpClient.callTool(
        CallToolRequest(
          name: 'flutter_screenshot',
          arguments: {'delayMs': 120},
        ),
      );

      verify(() => mockClient.screenshot(pixelRatio: 1.0, delayMs: 120))
          .called(1);
    });

    test('rejects negative delay', () async {
      final result = await mcpClient.callTool(
        CallToolRequest(
          name: 'flutter_screenshot',
          arguments: {'delayMs': -1},
        ),
      );

      expect(result.isError, isTrue);
      final json = jsonDecode((result.content[0] as TextContent).text)
          as Map<String, dynamic>;
      expect(json['error'], contains('delayMs must be >= 0'));
      expect(json['_meta']['startedAtUtc'], isA<String>());
    });

    test('returns error on failure', () async {
      when(() => mockClient.screenshot(
            pixelRatio: any(named: 'pixelRatio'),
            delayMs: any(named: 'delayMs'),
          )).thenThrow(Exception('Connection refused'));

      final result = await mcpClient.callTool(
        CallToolRequest(name: 'flutter_screenshot', arguments: {}),
      );

      expect(result.isError, isTrue);
      final json = jsonDecode((result.content[0] as TextContent).text)
          as Map<String, dynamic>;
      expect(json['error'], contains('Screenshot failed'));
    });
  });

  group('widget_tree tool', () {
    test('returns tree JSON on success', () async {
      final tree = WidgetNode(
        type: 'MaterialApp',
        children: [
          WidgetNode(type: 'Scaffold', children: [
            WidgetNode(type: 'Text', text: 'Hello'),
          ]),
        ],
      );
      when(() => mockClient.widgetTreeWithTiming(depth: any(named: 'depth')))
          .thenAnswer(
              (_) async => (tree: tree, captureTimeMs: 2, roundTripMs: 5));

      final result = await mcpClient.callTool(
        CallToolRequest(name: 'flutter_widget_tree', arguments: {}),
      );

      expect(result.isError, isNot(true));
      final text = (result.content[0] as TextContent).text;
      final json = jsonDecode(text) as Map<String, dynamic>;
      expect(json['type'], 'MaterialApp');
      expect(json['children'][0]['type'], 'Scaffold');
      expect(json['children'][0]['children'][0]['text'], 'Hello');
      expect(json['_meta']['captureTimeMs'], 2);
      expect(json['_meta']['roundTripMs'], 5);
    });

    test('passes depth parameter', () async {
      when(() => mockClient.widgetTreeWithTiming(depth: 5))
          .thenAnswer((_) async => (
                tree: WidgetNode(type: 'Root'),
                captureTimeMs: 1,
                roundTripMs: 2,
              ));

      await mcpClient.callTool(
        CallToolRequest(
          name: 'flutter_widget_tree',
          arguments: {'depth': 5},
        ),
      );

      verify(() => mockClient.widgetTreeWithTiming(depth: 5)).called(1);
    });

    test('passes focus parameters', () async {
      when(() => mockClient.widgetTreeWithTiming(
            depth: 4,
            x: 120.0,
            y: 240.0,
            ancestorLevels: 3,
          )).thenAnswer((_) async => (
            tree: WidgetNode(type: 'Container'),
            captureTimeMs: 1,
            roundTripMs: 2,
          ));

      final result = await mcpClient.callTool(
        CallToolRequest(
          name: 'flutter_widget_tree',
          arguments: {'depth': 4, 'x': 120.0, 'y': 240.0, 'ancestorLevels': 3},
        ),
      );

      final json = jsonDecode((result.content[0] as TextContent).text)
          as Map<String, dynamic>;
      expect(json['type'], 'Container');
      expect(json['_meta']['focusPoint']['x'], 120.0);
      expect(json['_meta']['ancestorLevels'], 3);
      verify(() => mockClient.widgetTreeWithTiming(
            depth: 4,
            x: 120.0,
            y: 240.0,
            ancestorLevels: 3,
          )).called(1);
    });

    test('rejects incomplete focus parameters', () async {
      final result = await mcpClient.callTool(
        CallToolRequest(
          name: 'flutter_widget_tree',
          arguments: {'x': 120.0},
        ),
      );

      expect(result.isError, isTrue);
      final json = jsonDecode((result.content[0] as TextContent).text)
          as Map<String, dynamic>;
      expect(json['error'], contains('x and y must be provided together'));
    });
  });

  group('tap tool', () {
    test('returns result on success', () async {
      when(() => mockClient.tap(any(), any()))
          .thenAnswer((_) async => TapResult(
                success: true,
                executionTimeMs: 1,
                roundTripMs: 5,
              ));

      final result = await mcpClient.callTool(
        CallToolRequest(
          name: 'flutter_tap',
          arguments: {'x': 100.0, 'y': 200.0},
        ),
      );

      expect(result.isError, isNot(true));
      final json = jsonDecode((result.content[0] as TextContent).text);
      expect(json['success'], isTrue);
      expect(json['_meta']['executionTimeMs'], 1);
      expect(json['_meta']['roundTripMs'], 5);
      verify(() => mockClient.tap(100.0, 200.0)).called(1);
    });

    test('returns error on failure', () async {
      when(() => mockClient.tap(any(), any()))
          .thenThrow(Exception('No widget at position'));

      final result = await mcpClient.callTool(
        CallToolRequest(
          name: 'flutter_tap',
          arguments: {'x': 0.0, 'y': 0.0},
        ),
      );

      expect(result.isError, isTrue);
    });
  });

  group('app_info tool', () {
    test('returns app info on success', () async {
      when(() => mockClient.appInfo()).thenAnswer((_) async => AppInfo(
            screenWidth: 393.0,
            screenHeight: 852.0,
            pixelRatio: 3.0,
            platform: 'macos',
            darkMode: false,
            bridgeVersion: '0.2.0',
            currentRoute: '/',
            locale: 'en_US',
          ));

      final result = await mcpClient.callTool(
        CallToolRequest(name: 'flutter_app_info', arguments: {}),
      );

      expect(result.isError, isNot(true));
      final json = jsonDecode((result.content[0] as TextContent).text);
      expect(json['screenWidth'], 393.0);
      expect(json['platform'], 'macos');
      expect(json['currentRoute'], '/');
      expect(json['locale'], 'en_US');
      expect(json['mcpServerVersion'], '0.2.0');
      expect(json['mcpVersionStatus'], 'up-to-date');
      expect(json['_meta']['startedAtUtc'], isA<String>());
    });

    test('returns an update hint when the bridge is newer than the MCP server',
        () async {
      when(() => mockClient.appInfo()).thenAnswer((_) async => AppInfo(
            screenWidth: 393.0,
            screenHeight: 852.0,
            pixelRatio: 3.0,
            platform: 'macos',
            darkMode: false,
            bridgeVersion: '0.2.1',
          ));

      final result = await mcpClient.callTool(
        CallToolRequest(name: 'flutter_app_info', arguments: {}),
      );

      final json = jsonDecode((result.content[0] as TextContent).text)
          as Map<String, dynamic>;
      expect(json['mcpVersionStatus'], 'update-recommended');
      expect(json['updateHint'], contains('Update turbo_bridge_mcp'));
    });
  });

  group('find_widget tool', () {
    test('finds widget by text', () async {
      when(() => mockClient.find(
              text: 'Counter', key: null, type: null, limit: 10))
          .thenAnswer((_) async => const FindResponse(
                found: true,
                count: 1,
                searchTimeMs: 4,
                roundTripMs: 7,
                results: [
                  FoundWidgetResult(
                    type: 'Text',
                    text: 'Counter: 0',
                    center: (x: 140.0, y: 210.0),
                    bounds: (x: 100.0, y: 200.0, w: 80.0, h: 20.0),
                  ),
                ],
              ));

      final result = await mcpClient.callTool(
        CallToolRequest(
          name: 'flutter_find_widget',
          arguments: {'text': 'Counter'},
        ),
      );

      expect(result.isError, isNot(true));
      final json = jsonDecode((result.content[0] as TextContent).text);
      expect(json['found'], isTrue);
      expect(json['count'], 1);
      expect(json['results'][0]['text'], 'Counter: 0');
      expect(json['results'][0]['center']['x'], 140.0);
      expect(json['results'][0]['center']['y'], 210.0);
      expect(json['_meta']['searchTimeMs'], 4);
      expect(json['_meta']['roundTripMs'], 7);
    });

    test('finds widget by key', () async {
      when(() => mockClient.find(
              text: null, key: 'increment_btn', type: null, limit: 10))
          .thenAnswer((_) async => const FindResponse(
                found: true,
                count: 1,
                searchTimeMs: 2,
                roundTripMs: 5,
                results: [
                  FoundWidgetResult(
                      type: 'FloatingActionButton', key: 'increment_btn')
                ],
              ));

      final result = await mcpClient.callTool(
        CallToolRequest(
          name: 'flutter_find_widget',
          arguments: {'key': 'increment_btn'},
        ),
      );

      final json = jsonDecode((result.content[0] as TextContent).text);
      expect(json['found'], isTrue);
      expect(json['results'][0]['key'], 'increment_btn');
    });

    test('finds widget by type', () async {
      when(() => mockClient.find(
              text: null, key: null, type: 'ElevatedButton', limit: 10))
          .thenAnswer((_) async => const FindResponse(
                found: true,
                count: 2,
                searchTimeMs: 3,
                roundTripMs: 6,
                results: [
                  FoundWidgetResult(type: 'ElevatedButton'),
                  FoundWidgetResult(type: 'ElevatedButton'),
                ],
              ));

      final result = await mcpClient.callTool(
        CallToolRequest(
          name: 'flutter_find_widget',
          arguments: {'type': 'ElevatedButton'},
        ),
      );

      final json = jsonDecode((result.content[0] as TextContent).text);
      expect(json['found'], isTrue);
      expect(json['count'], 2);
    });

    test('returns not found when no match', () async {
      when(() => mockClient.find(
              text: 'nonexistent', key: null, type: null, limit: 10))
          .thenAnswer((_) async => const FindResponse(
                found: false,
                count: 0,
                searchTimeMs: 1,
                roundTripMs: 4,
                results: [],
              ));

      final result = await mcpClient.callTool(
        CallToolRequest(
          name: 'flutter_find_widget',
          arguments: {'text': 'nonexistent'},
        ),
      );

      final json = jsonDecode((result.content[0] as TextContent).text);
      expect(json['found'], isFalse);
      expect(json['_meta']['searchTimeMs'], 1);
    });

    test('returns error when no criteria given', () async {
      final result = await mcpClient.callTool(
        CallToolRequest(
          name: 'flutter_find_widget',
          arguments: {},
        ),
      );

      expect(result.isError, isTrue);
      final json = jsonDecode((result.content[0] as TextContent).text)
          as Map<String, dynamic>;
      expect(json['error'], contains('Provide at least one of'));
    });
  });

  group('resources', () {
    test('app info resource returns JSON', () async {
      when(() => mockClient.appInfo()).thenAnswer((_) async => AppInfo(
            screenWidth: 393.0,
            screenHeight: 852.0,
            pixelRatio: 3.0,
            platform: 'macos',
            darkMode: false,
            bridgeVersion: '0.1.6',
          ));

      final result = await mcpClient.readResource(
        ReadResourceRequest(uri: 'flutter://app/info'),
      );

      final text = (result.contents[0] as TextResourceContents).text;
      final json = jsonDecode(text) as Map<String, dynamic>;
      expect(json['platform'], 'macos');
      expect(json['mcpServerVersion'], '0.2.0');
      expect(json['_meta']['startedAtUtc'], isA<String>());
    });

    test('widget tree resource returns JSON', () async {
      when(() => mockClient.widgetTreeWithTiming(depth: 10))
          .thenAnswer((_) async => (
                tree: WidgetNode(type: 'MaterialApp'),
                captureTimeMs: 2,
                roundTripMs: 5,
              ));

      final result = await mcpClient.readResource(
        ReadResourceRequest(uri: 'flutter://app/tree'),
      );

      final text = (result.contents[0] as TextResourceContents).text;
      final json = jsonDecode(text);
      expect(json['type'], 'MaterialApp');
      expect(json['_meta']['captureTimeMs'], 2);
    });
  });

  group('prompts', () {
    test('flutter_inspect generates inspection prompt', () async {
      final result = await mcpClient.getPrompt(
        GetPromptRequest(name: 'flutter_inspect'),
      );

      expect(result.messages.length, 1);
      expect(result.messages[0].role, PromptMessageRole.user);
      final text = (result.messages[0].content as TextContent).text;
      expect(text, contains('flutter_app_info'));
      expect(text, contains('flutter_screenshot'));
      expect(text, contains('flutter_widget_tree'));
    });

    test('flutter_inspect with focus includes focus area', () async {
      final result = await mcpClient.getPrompt(
        GetPromptRequest(
          name: 'flutter_inspect',
          arguments: {'focus': 'accessibility'},
        ),
      );

      final text = (result.messages[0].content as TextContent).text;
      expect(text, contains('accessibility'));
    });
  });
}
