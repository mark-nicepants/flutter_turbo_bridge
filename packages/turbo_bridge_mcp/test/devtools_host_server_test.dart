import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:turbo_bridge_mcp/turbo_bridge_mcp.dart';

void main() {
  group('DevToolsHostServer', () {
    late HttpServer device;
    late DevToolsHostServer host;
    late int hostPort;

    setUp(() async {
      device = await shelf_io.serve(_fakeDevice, 'localhost', 0);
      host =
          DevToolsHostServer(bridgeHost: 'localhost', bridgePort: device.port);
      hostPort = await host.start(port: 0);
    });

    tearDown(() async {
      await host.stop();
      await device.close(force: true);
    });

    Future<HttpClientResponse> get(String path) async {
      final client = HttpClient();
      final req =
          await client.getUrl(Uri.parse('http://localhost:$hostPort$path'));
      return req.close();
    }

    test('serves the embedded UI bundle at /', () async {
      final resp = await get('/');
      expect(resp.statusCode, 200);
      expect(resp.headers.value('content-type'), startsWith('text/html'));
      final body = await resp.transform(utf8.decoder).join();
      expect(body, contains('<script'));
    });

    test('serves the SPA shell for unknown non-api paths', () async {
      final resp = await get('/some/deep/link');
      expect(resp.statusCode, 200);
      expect(resp.headers.value('content-type'), startsWith('text/html'));
    });

    test('proxies /api/* to the device with the api/ prefix stripped',
        () async {
      final resp = await get('/api/health');
      expect(resp.statusCode, 200);
      final json = jsonDecode(await resp.transform(utf8.decoder).join());
      expect(json['status'], 'ok');
    });

    test('forwards the query string on proxied requests', () async {
      final resp = await get('/api/devtools/logs?level=error');
      final json = jsonDecode(await resp.transform(utf8.decoder).join()) as Map;
      expect(json['query'], 'level=error');
    });

    test('forwards the request body on proxied POSTs', () async {
      final client = HttpClient();
      final req =
          await client.postUrl(Uri.parse('http://localhost:$hostPort/api/tap'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'x': 1, 'y': 2}));
      final resp = await req.close();
      final json = jsonDecode(await resp.transform(utf8.decoder).join()) as Map;
      expect(json['echo'], {'x': 1, 'y': 2});
    });

    test('streams /events through the proxy without buffering', () async {
      final client = HttpClient();
      final req =
          await client.getUrl(Uri.parse('http://localhost:$hostPort/events'));
      final resp = await req.close();
      expect(resp.statusCode, 200);
      expect(
          resp.headers.value('content-type'), startsWith('text/event-stream'));

      final chunks = <String>[];
      final sub = resp.transform(utf8.decoder).listen(chunks.add);
      // The fake device emits a ping ~10ms in; allow it to arrive.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(chunks.join(), contains('event: ping'));
      await sub.cancel();
      req.abort();
      client.close(force: true);
    });

    test('returns 502 when the device is unreachable', () async {
      final lonely = DevToolsHostServer(bridgeHost: 'localhost', bridgePort: 1);
      final port = await lonely.start(port: 0);
      final client = HttpClient();
      final req =
          await client.getUrl(Uri.parse('http://localhost:$port/api/health'));
      final resp = await req.close();
      expect(resp.statusCode, 502);
      await resp.drain<void>();
      await lonely.stop();
    });
  });

  group('DevToolsHostServer __host control endpoints', () {
    test('GET /__host/status reports bridge + adb state', () async {
      final server = DevToolsHostServer(
        bridgeHost: 'localhost',
        bridgePort: 8888,
        reachabilityProbe: (_, __, ___) async => false,
        processRunner: (exe, args) async => ProcessResult(
            1, 0, 'List of devices attached\nserial\tdevice\n', ''),
      );
      final port = await server.start(port: 0);
      final client = HttpClient();
      final req = await client
          .getUrl(Uri.parse('http://localhost:$port/__host/status'));
      final resp = await req.close();
      final json = jsonDecode(await resp.transform(utf8.decoder).join()) as Map;
      expect(json['bridgeReachable'], isFalse);
      expect(json['adbAvailable'], isTrue);
      expect(json['deviceConnected'], isTrue);
      expect(json['bridgePort'], 8888);
      await server.stop();
    });

    test('POST /__host/reconnect runs adb forward and re-probes', () async {
      final commands = <String>[];
      var forwarded = false;
      final server = DevToolsHostServer(
        bridgeHost: 'localhost',
        bridgePort: 8888,
        reachabilityProbe: (_, __, ___) async => forwarded,
        processRunner: (exe, args) async {
          commands.add(args.join(' '));
          if (args.first == 'devices') {
            return ProcessResult(
              1,
              0,
              'List of devices attached\nserial\tdevice\n',
              '',
            );
          }
          if (args.first == 'forward') {
            forwarded = true;
            return ProcessResult(1, 0, '', '');
          }
          return ProcessResult(1, 1, '', 'unexpected');
        },
      );
      final port = await server.start(port: 0);
      final client = HttpClient();
      final req = await client
          .postUrl(Uri.parse('http://localhost:$port/__host/reconnect'));
      final resp = await req.close();
      final json = jsonDecode(await resp.transform(utf8.decoder).join()) as Map;
      expect(json['forwarded'], isTrue);
      expect(json['bridgeReachable'], isTrue);
      expect(commands, contains('forward tcp:8888 tcp:8888'));
      await server.stop();
    });

    test('GET /__host/packages resolves package: dirs from package_config',
        () async {
      final tmp = Directory.systemTemp.createTempSync('host_pkgs_test');
      Directory('${tmp.path}/.dart_tool').createSync(recursive: true);
      File('${tmp.path}/.dart_tool/package_config.json').writeAsStringSync(
        '{ "configVersion": 2, "packages": '
        '[ { "name": "my_app", "rootUri": "../", "packageUri": "lib/" } ] }',
      );
      final server = DevToolsHostServer(
        bridgeHost: 'localhost',
        bridgePort: 8888,
        projectRoot: tmp.path,
      );
      final port = await server.start(port: 0);
      final client = HttpClient();
      final req = await client
          .getUrl(Uri.parse('http://localhost:$port/__host/packages'));
      final resp = await req.close();
      final json = jsonDecode(await resp.transform(utf8.decoder).join()) as Map;
      expect((json['packages'] as Map)['my_app'], contains('lib'));
      await server.stop();
      tmp.deleteSync(recursive: true);
    });

    test('POST /__host/reconnect reports when no device is connected',
        () async {
      final server = DevToolsHostServer(
        bridgeHost: 'localhost',
        bridgePort: 8888,
        reachabilityProbe: (_, __, ___) async => false,
        processRunner: (exe, args) async =>
            ProcessResult(1, 0, 'List of devices attached\n', ''),
      );
      final port = await server.start(port: 0);
      final client = HttpClient();
      final req = await client
          .postUrl(Uri.parse('http://localhost:$port/__host/reconnect'));
      final resp = await req.close();
      final json = jsonDecode(await resp.transform(utf8.decoder).join()) as Map;
      expect(json['bridgeReachable'], isFalse);
      expect(json['deviceConnected'], isFalse);
      expect(json['message'], contains('No Android device'));
      await server.stop();
    });
  });
}

Future<Response> _fakeDevice(Request request) async {
  final path = request.url.path;
  switch (path) {
    case 'health':
      return Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'content-type': 'application/json'},
      );
    case 'devtools/logs':
      return Response.ok(
        jsonEncode({'entries': const [], 'query': request.url.query}),
        headers: {'content-type': 'application/json'},
      );
    case 'tap':
      final body = jsonDecode(await request.readAsString());
      return Response.ok(
        jsonEncode({'echo': body}),
        headers: {'content-type': 'application/json'},
      );
    case 'events':
      final controller = StreamController<List<int>>();
      controller.add(utf8.encode(': connected\n\n'));
      Timer(const Duration(milliseconds: 10), () {
        if (!controller.isClosed) {
          controller.add(utf8.encode('event: ping\ndata: {}\n\n'));
        }
      });
      return Response.ok(
        controller.stream,
        headers: {'content-type': 'text/event-stream'},
        context: {'shelf.io.buffer_output': false},
      );
    default:
      return Response.notFound('no');
  }
}
