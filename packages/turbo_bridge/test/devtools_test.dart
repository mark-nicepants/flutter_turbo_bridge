import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:turbo_bridge/src/devtools/devtools_router.dart';
import 'package:turbo_bridge/src/devtools/event_bus.dart';
import 'package:turbo_bridge/src/devtools/log_sink.dart';
import 'package:turbo_bridge/src/devtools/request_log.dart';
import 'package:turbo_bridge/src/devtools/static_handler.dart';
import 'package:turbo_bridge/src/server/router.dart';
import 'package:turbo_bridge/turbo_bridge.dart';

LogEntry _wrappedInfoLog(LogSink sink) {
  return sink.info('wrapped', sourceFrameSkip: 1);
}

class _FakeAppInfoService extends AppInfoService {
  @override
  Map<String, dynamic> getInfo() {
    return {
      'screenWidth': 390.0,
      'screenHeight': 844.0,
      'pixelRatio': 3.0,
      'platform': 'android',
      'darkMode': false,
      'currentRoute': '/home',
      'bridgeVersion': 'test',
      'locale': 'en',
    };
  }
}

void main() {
  group('RequestLog', () {
    test('records entries with monotonic ids', () {
      final log = RequestLog(capacity: 10);
      final a = log.record(
          method: 'GET',
          path: '/health',
          query: null,
          status: 200,
          durationMs: 1,
          remoteAddress: '127.0.0.1');
      final b = log.record(
          method: 'POST',
          path: '/tap',
          query: null,
          status: 200,
          durationMs: 3,
          remoteAddress: '127.0.0.1');
      expect(a.id, 1);
      expect(b.id, 2);
      expect(log.snapshot().map((e) => e.id), [1, 2]);
    });

    test('drops oldest entries past capacity', () {
      final log = RequestLog(capacity: 3);
      for (var i = 0; i < 5; i++) {
        log.record(
            method: 'GET',
            path: '/$i',
            query: null,
            status: 200,
            durationMs: 0,
            remoteAddress: null);
      }
      final entries = log.snapshot();
      expect(entries.length, 3);
      expect(entries.map((e) => e.path), ['/2', '/3', '/4']);
    });

    test('serializes entries to JSON with timestamp', () {
      final log = RequestLog();
      final e = log.record(
          method: 'GET',
          path: '/info',
          query: 'depth=2',
          status: 200,
          durationMs: 5,
          remoteAddress: '10.0.0.5');
      final json = e.toJson();
      expect(json['method'], 'GET');
      expect(json['path'], '/info');
      expect(json['query'], 'depth=2');
      expect(json['status'], 200);
      expect(json['durationMs'], 5);
      expect(json['remoteAddress'], '10.0.0.5');
      expect(DateTime.parse(json['timestamp'] as String).isUtc, isTrue);
    });
  });

  group('RequestLog body excerpts', () {
    test('records request and response body bytes as text', () {
      final log = RequestLog();
      final entry = log.record(
        method: 'POST',
        path: '/tap',
        query: null,
        status: 200,
        durationMs: 1,
        remoteAddress: '127.0.0.1',
        requestBodyBytes: '{"x":1,"y":2}'.codeUnits,
        responseBodyBytes: '{"success":true}'.codeUnits,
      );
      expect(entry.requestBody, '{"x":1,"y":2}');
      expect(entry.requestBodySize, 13);
      expect(entry.responseBody, '{"success":true}');
      expect(entry.responseBodyTruncated, isFalse);
    });

    test('marks body as truncated past 16 KB', () {
      final log = RequestLog();
      final big = List<int>.filled(20 * 1024, 0x41); // 'A' * 20k
      final entry = log.record(
        method: 'GET',
        path: '/big',
        query: null,
        status: 200,
        durationMs: 1,
        remoteAddress: null,
        responseBodyBytes: big,
      );
      expect(entry.responseBodySize, 20 * 1024);
      expect(entry.responseBodyTruncated, isTrue);
      expect(entry.responseBody!.length, 16 * 1024);
    });

    test('detects binary bodies and replaces with marker', () {
      final log = RequestLog();
      // 64 bytes of nulls — clearly binary.
      final binary = List<int>.filled(64, 0);
      final entry = log.record(
        method: 'GET',
        path: '/screenshot',
        query: null,
        status: 200,
        durationMs: 1,
        remoteAddress: null,
        responseBodyBytes: binary,
      );
      expect(entry.responseBody, contains('<binary'));
      expect(entry.responseBody, contains('64 bytes'));
    });

    test('byId returns null when entry missing', () {
      final log = RequestLog();
      expect(log.byId(42), isNull);
    });

    test('clear empties the buffer', () {
      final log = RequestLog();
      log.record(
        method: 'GET',
        path: '/x',
        query: null,
        status: 200,
        durationMs: 0,
        remoteAddress: null,
      );
      log.clear();
      expect(log.length, 0);
    });
  });

  group('LogSink', () {
    test('normalizeSourceFileForDevTools resolves package URIs when possible',
        () {
      final resolved = normalizeSourceFileForDevTools(
        'package:sdb_octopus/shared/utils/sdb_print.dart',
        packageUriResolver: (packageUri) => Uri.parse(
          'file:///Users/mark/Developer/sdb/SDBGroep/src/'
          'SDB.Octopus/lib/shared/utils/sdb_print.dart',
        ),
      );

      expect(
        resolved,
        'file:///Users/mark/Developer/sdb/SDBGroep/src/'
        'SDB.Octopus/lib/shared/utils/sdb_print.dart',
      );
    });

    test('normalizeSourceFileForDevTools keeps package URIs when unresolved',
        () {
      final resolved = normalizeSourceFileForDevTools(
        'package:sdb_octopus/shared/utils/sdb_print.dart',
        packageUriResolver: (_) => null,
      );

      expect(resolved, 'package:sdb_octopus/shared/utils/sdb_print.dart');
    });

    test('level convenience methods set the right level', () {
      final bus = DevToolsEventBus();
      final sink = LogSink(bus: bus);
      sink.trace('t');
      sink.debug('d');
      sink.info('i');
      sink.warn('w', error: 'something');
      sink.error('e', error: Exception('boom'), stackTrace: StackTrace.current);
      final levels = sink.snapshot().map((e) => e.level).toList();
      expect(levels, [
        LogLevel.trace,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warn,
        LogLevel.error,
      ]);
      expect(sink.snapshot().last.errorString, contains('Exception: boom'));
      bus.close();
    });

    test('emits a log event onto the bus when add() is called', () async {
      final bus = DevToolsEventBus();
      final sink = LogSink(bus: bus);
      final events = <String>[];
      final sub = bus.stream.listen((e) => events.add(e.type));
      sink.info('hello');
      await Future<void>.delayed(Duration.zero);
      expect(events, ['log']);
      await sub.cancel();
      await bus.close();
    });

    test('drops oldest entries past capacity', () {
      final bus = DevToolsEventBus();
      final sink = LogSink(bus: bus, capacity: 3);
      for (var i = 0; i < 5; i++) {
        sink.info('m$i');
      }
      final messages = sink.snapshot().map((e) => e.message).toList();
      expect(messages, ['m2', 'm3', 'm4']);
      bus.close();
    });

    test('clear empties the buffer', () {
      final bus = DevToolsEventBus();
      final sink = LogSink(bus: bus);
      sink.info('x');
      sink.clear();
      expect(sink.length, 0);
      bus.close();
    });

    test('LogEntry.toJson omits null optional fields', () {
      final bus = DevToolsEventBus();
      final sink = LogSink(bus: bus);
      final entry = sink.add(message: 'plain', captureSource: false);
      final json = entry.toJson();
      expect(json.containsKey('category'), isFalse);
      expect(json.containsKey('data'), isFalse);
      expect(json.containsKey('error'), isFalse);
      expect(json.containsKey('sourceFile'), isFalse);
      expect(json['level'], 'info');
      bus.close();
    });

    test('captures the caller source location from StackTrace', () {
      final bus = DevToolsEventBus();
      final sink = LogSink(bus: bus);
      final entry = sink.info('here'); // ← this is the line we expect
      // The frame should point at THIS test file (not log_sink.dart).
      expect(entry.sourceFile, isNotNull);
      expect(entry.sourceFile, contains('devtools_test.dart'));
      expect(entry.sourceLine, isNotNull);
      expect(entry.sourceLine!, greaterThan(0));
      expect(entry.sourceColumn, isNotNull);
      bus.close();
    });

    test('sourceFrameSkip skips wrapper helpers when requested', () {
      final bus = DevToolsEventBus();
      final sink = LogSink(bus: bus);
      final entry = _wrappedInfoLog(sink); // expect this file, not helper body
      expect(entry.sourceFile, isNotNull);
      expect(entry.sourceFile, contains('devtools_test.dart'));
      expect(entry.sourceLine, isNotNull);
      expect(entry.sourceLine!, greaterThan(0));
      bus.close();
    });

    test('captureSource: false skips the stack-trace scan', () {
      final bus = DevToolsEventBus();
      final sink = LogSink(bus: bus);
      final entry = sink.add(message: 'nope', captureSource: false);
      expect(entry.sourceFile, isNull);
      expect(entry.sourceLine, isNull);
      bus.close();
    });
  });

  group('NavigationLog', () {
    test('push records a navigation entry and emits an event', () async {
      final bus = DevToolsEventBus();
      final nav = NavigationLog(bus: bus);
      final events = <String>[];
      final sub = bus.stream.listen((e) => events.add(e.type));
      nav.push('/home');
      nav.push('/cart', from: '/home');
      await Future<void>.delayed(Duration.zero);
      expect(events, ['navigation', 'navigation']);
      expect(nav.snapshot().map((e) => e.route).toList(), ['/home', '/cart']);
      expect(nav.snapshot().last.from, '/home');
      await sub.cancel();
      await bus.close();
    });

    test('drops oldest entries past capacity', () {
      final bus = DevToolsEventBus();
      final nav = NavigationLog(bus: bus, capacity: 2);
      nav.push('/a');
      nav.push('/b');
      nav.push('/c');
      expect(nav.snapshot().map((e) => e.route).toList(), ['/b', '/c']);
      bus.close();
    });

    test('clear empties the buffer', () {
      final bus = DevToolsEventBus();
      final nav = NavigationLog(bus: bus);
      nav.push('/x');
      nav.clear();
      expect(nav.length, 0);
      bus.close();
    });
  });

  group('NetworkLog', () {
    test('emits a network event and exposes byId', () async {
      final bus = DevToolsEventBus();
      final net = NetworkLog(bus: bus);
      final events = <String>[];
      final sub = bus.stream.listen((e) => events.add(e.type));
      final call = net.record(
        method: 'POST',
        url: 'https://x/y',
        status: 201,
        durationMs: 7,
        requestBody: '{"a":1}',
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, ['network']);
      expect(net.byId(call.id), isNotNull);
      expect(call.requestBodySize, '{"a":1}'.length);
      await sub.cancel();
      await bus.close();
    });

    test('infers responseBodySize from responseBody when not given', () {
      final bus = DevToolsEventBus();
      final net = NetworkLog(bus: bus);
      final call = net.record(
        method: 'GET',
        url: 'https://x/y',
        responseBody: 'hello',
      );
      expect(call.responseBodySize, 5);
      bus.close();
    });

    test('byId returns null when missing, clear empties the buffer', () {
      final bus = DevToolsEventBus();
      final net = NetworkLog(bus: bus);
      expect(net.byId(99), isNull);
      net.record(method: 'GET', url: 'x');
      net.clear();
      expect(net.length, 0);
      bus.close();
    });

    test('drops oldest entries past capacity', () {
      final bus = DevToolsEventBus();
      final net = NetworkLog(bus: bus, capacity: 2);
      net.record(method: 'GET', url: 'a');
      net.record(method: 'GET', url: 'b');
      net.record(method: 'GET', url: 'c');
      expect(net.snapshot().map((e) => e.url).toList(), ['b', 'c']);
      bus.close();
    });

    test('start/complete records duration from the start timestamp', () async {
      final bus = DevToolsEventBus();
      final net = NetworkLog(bus: bus);
      final inflight = net.start(
        method: 'POST',
        url: 'https://api.example.com/items',
        requestHeaders: {'content-type': 'application/json'},
        requestBody: '{"name":"a"}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
      inflight.complete(
        status: 201,
        responseHeaders: {'content-type': 'application/json'},
        responseBody: '{"id":1}',
      );
      final calls = net.snapshot();
      expect(calls, hasLength(1));
      final call = calls.single;
      expect(call.method, 'POST');
      expect(call.status, 201);
      expect(call.requestBody, '{"name":"a"}');
      expect(call.responseBody, '{"id":1}');
      expect(call.durationMs!, greaterThanOrEqualTo(15));
      bus.close();
    });

    test('start/complete is idempotent', () {
      final bus = DevToolsEventBus();
      final net = NetworkLog(bus: bus);
      final inflight = net.start(method: 'GET', url: 'x');
      inflight.complete(status: 200);
      inflight.complete(status: 500); // ignored
      inflight.fail(Exception('also ignored'));
      expect(net.snapshot(), hasLength(1));
      expect(net.snapshot().single.status, 200);
      expect(inflight.isDone, isTrue);
      bus.close();
    });

    test('start + fail records the error', () {
      final bus = DevToolsEventBus();
      final net = NetworkLog(bus: bus);
      final inflight = net.start(method: 'GET', url: 'x');
      inflight.fail(Exception('boom'));
      expect(net.snapshot().single.error, contains('boom'));
      bus.close();
    });

    test('start + cancel drops the entry', () {
      final bus = DevToolsEventBus();
      final net = NetworkLog(bus: bus);
      final inflight = net.start(method: 'GET', url: 'x');
      inflight.cancel();
      expect(net.snapshot(), isEmpty);
      bus.close();
    });

    test('NetworkCall.toDetailJson includes optional fields', () {
      final bus = DevToolsEventBus();
      final net = NetworkLog(bus: bus);
      final call = net.record(
        method: 'POST',
        url: 'https://x/y',
        status: 500,
        requestHeaders: {'authorization': 'Bearer ***'},
        requestBody: '{}',
        responseHeaders: {'content-type': 'application/json'},
        responseBody: '{"err":"nope"}',
        error: Exception('upstream'),
      );
      final detail = call.toDetailJson();
      expect(detail['requestHeaders'], {'authorization': 'Bearer ***'});
      expect(detail['responseHeaders'], {'content-type': 'application/json'});
      expect(detail['error'], contains('Exception: upstream'));
      bus.close();
    });
  });

  group('DevToolsEventBus', () {
    test('broadcasts events to multiple subscribers', () async {
      final bus = DevToolsEventBus();
      final received = <List<String>>[];
      final subA = <String>[];
      final subB = <String>[];
      final aDone = bus.stream.listen((e) => subA.add(e.type));
      final bDone = bus.stream.listen((e) => subB.add(e.type));

      bus.emit(DevToolsEvent('request', {'path': '/a'}));
      bus.emit(DevToolsEvent('route', {'name': '/home'}));

      // Allow microtasks to deliver events.
      await Future<void>.delayed(Duration.zero);
      received.add(subA);
      received.add(subB);

      expect(subA, ['request', 'route']);
      expect(subB, ['request', 'route']);

      await aDone.cancel();
      await bDone.cancel();
      await bus.close();
    });

    test('emit after close is a no-op', () async {
      final bus = DevToolsEventBus();
      await bus.close();
      bus.emit(DevToolsEvent('request', const {}));
    });
  });

  group('DevToolsStaticHandler', () {
    final fixtureAssets = <String, DevToolsAsset>{
      'index.html': const DevToolsAsset.text(
          '<html><body>shell</body></html>', 'text/html; charset=utf-8'),
      'styles.css': const DevToolsAsset.text('body { color: red }', 'text/css'),
    };

    test('serves /index.html by default', () {
      final handler = DevToolsStaticHandler(assets: fixtureAssets);
      final res = handler.handle(Request('GET', Uri.parse('http://x:8889/')));
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], startsWith('text/html'));
    });

    test('unknown paths fall back to the SPA shell', () {
      final handler = DevToolsStaticHandler(assets: fixtureAssets);
      final res = handler
          .handle(Request('GET', Uri.parse('http://x:8889/some/deep/link')));
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], startsWith('text/html'));
    });

    test('serves a known asset with its content type', () {
      final handler = DevToolsStaticHandler(assets: fixtureAssets);
      final res =
          handler.handle(Request('GET', Uri.parse('http://x:8889/styles.css')));
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], 'text/css');
    });

    test('404 when no assets are loaded at all', () {
      final handler = DevToolsStaticHandler(assets: const {});
      final res =
          handler.handle(Request('GET', Uri.parse('http://x:8889/anything')));
      expect(res.statusCode, 404);
    });
  });

  group('DevToolsRouter', () {
    late RequestLog log;
    late DevToolsEventBus bus;
    late BridgeRouter bridgeRouter;
    late DevToolsRouter router;

    setUp(() {
      log = RequestLog();
      bus = DevToolsEventBus();
      bridgeRouter = BridgeRouter(
        screenshotService: ScreenshotService(),
        widgetTreeService: WidgetTreeService(),
        gestureService: GestureService(),
        appInfoService: AppInfoService(),
        findService: FindService(),
      );
      router = DevToolsRouter(
        bridgeRouter: bridgeRouter,
        eventBus: bus,
        requestLog: log,
        logs: LogSink(bus: bus),
        network: NetworkLog(bus: bus),
        navigation: NavigationLog(bus: bus),
        staticHandler: DevToolsStaticHandler(assets: {
          'index.html': const DevToolsAsset.text(
              '<html><body>shell</body></html>', 'text/html; charset=utf-8'),
        }),
      );
    });

    tearDown(() async {
      await bus.close();
    });

    test('/api/devtools/requests returns the current log snapshot', () async {
      log.record(
          method: 'GET',
          path: '/health',
          query: null,
          status: 200,
          durationMs: 1,
          remoteAddress: '127.0.0.1');
      final res = await router.handler(
          Request('GET', Uri.parse('http://x:8889/api/devtools/requests')));
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect((body['entries'] as List).length, 1);
      expect((body['entries'] as List).first['path'], '/health');
    });

    test('mutating /api/* without x-turbo-devtools header is rejected',
        () async {
      final res = await router.handler(Request(
        'POST',
        Uri.parse('http://x:8889/api/tap'),
        body: jsonEncode({'x': 10, 'y': 20}),
        headers: const {'content-type': 'application/json'},
      ));
      expect(res.statusCode, 403);
    });

    test('GET /api/health is proxied to the bridge router', () async {
      final res = await router
          .handler(Request('GET', Uri.parse('http://x:8889/api/health')));
      expect(res.statusCode, 200);
      final json = jsonDecode(await res.readAsString());
      expect(json['status'], 'ok');
    });

    test('/api/devtools/logs returns app-pushed log entries', () async {
      final sink = LogSink(bus: bus);
      // Re-register router with the new sink so it serves it.
      router = DevToolsRouter(
        bridgeRouter: bridgeRouter,
        eventBus: bus,
        requestLog: log,
        logs: sink,
        network: NetworkLog(bus: bus),
        navigation: NavigationLog(bus: bus),
        staticHandler: DevToolsStaticHandler(assets: const {}),
      );
      sink.info('hello world', category: 'auth');
      sink.error('boom', category: 'net', error: Exception('nope'));

      final res = await router.handler(
          Request('GET', Uri.parse('http://x:8889/api/devtools/logs')));
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      final entries = body['entries'] as List;
      expect(entries.length, 2);
      expect(entries[0]['message'], 'hello world');
      expect(entries[1]['level'], 'error');
    });

    test('/api/devtools/network returns app-pushed network calls', () async {
      final net = NetworkLog(bus: bus);
      router = DevToolsRouter(
        bridgeRouter: bridgeRouter,
        eventBus: bus,
        requestLog: log,
        logs: LogSink(bus: bus),
        network: net,
        navigation: NavigationLog(bus: bus),
        staticHandler: DevToolsStaticHandler(assets: const {}),
      );
      final call = net.record(
        method: 'GET',
        url: 'https://api.example.com/users/1',
        status: 200,
        durationMs: 42,
        responseBody: '{"id":1}',
      );

      final list = await router.handler(
          Request('GET', Uri.parse('http://x:8889/api/devtools/network')));
      final entries =
          (jsonDecode(await list.readAsString()) as Map)['entries'] as List;
      expect(entries.length, 1);
      expect(entries.first['url'], 'https://api.example.com/users/1');

      final detail = await router.handler(Request(
          'GET', Uri.parse('http://x:8889/api/devtools/network/${call.id}')));
      final d = jsonDecode(await detail.readAsString()) as Map<String, dynamic>;
      expect(d['responseBody'], '{"id":1}');
    });

    test('/api/devtools/requests/:id returns full detail with bodies',
        () async {
      final entry = log.record(
        method: 'POST',
        path: '/tap',
        query: null,
        status: 200,
        durationMs: 1,
        remoteAddress: '127.0.0.1',
        requestHeaders: {'content-type': 'application/json'},
        requestBodyBytes: '{"x":1,"y":2}'.codeUnits,
        responseHeaders: {'content-type': 'application/json'},
        responseBodyBytes: '{"success":true}'.codeUnits,
      );

      final res = await router.handler(Request(
          'GET', Uri.parse('http://x:8889/api/devtools/requests/${entry.id}')));
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body['requestBody'], '{"x":1,"y":2}');
      expect(body['responseBody'], '{"success":true}');
      expect(
          (body['responseHeaders'] as Map)['content-type'], 'application/json');
    });

    test('/events opens an SSE stream and pushes emitted events', () async {
      final res = await router
          .handler(Request('GET', Uri.parse('http://x:8889/events')));
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], 'text/event-stream');

      final chunks = <String>[];
      final sub = res.read().listen((b) => chunks.add(utf8.decode(b)));

      // Let the initial comment flush, then emit.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      bus.emit(DevToolsEvent('request', {'path': '/x'}));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final combined = chunks.join();
      expect(combined, contains('event: request'));
      expect(combined, contains('"path":"/x"'));

      await sub.cancel();
    });
  });

  group('BridgeRouter new endpoints', () {
    late BridgeRouter router;
    late DevToolsEventBus bus;
    setUp(() {
      bus = DevToolsEventBus();
      router = BridgeRouter(
        screenshotService: ScreenshotService(),
        widgetTreeService: WidgetTreeService(),
        gestureService: GestureService(),
        appInfoService: AppInfoService(),
        findService: FindService(),
        logs: LogSink(bus: bus),
        network: NetworkLog(bus: bus),
      );
    });

    tearDown(() async {
      await bus.close();
    });

    test('/logs returns entries the sink has accumulated', () async {
      router.logs!.info('first');
      router.logs!.warn('second', category: 'auth');
      final res =
          await router.handler(Request('GET', Uri.parse('http://x:8888/logs')));
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      final entries = body['entries'] as List;
      expect(entries.length, 2);
      expect((entries.last as Map)['level'], 'warn');
    });

    test('/logs filters by minimum level', () async {
      router.logs!.debug('d');
      router.logs!.info('i');
      router.logs!.error('e');
      final res = await router
          .handler(Request('GET', Uri.parse('http://x:8888/logs?level=warn')));
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      final entries = body['entries'] as List;
      expect(entries.length, 1);
      expect((entries.first as Map)['level'], 'error');
    });

    test('/logs honours limit (returns the tail)', () async {
      for (var i = 0; i < 10; i++) {
        router.logs!.info('m$i');
      }
      final res = await router
          .handler(Request('GET', Uri.parse('http://x:8888/logs?limit=3')));
      final entries = (jsonDecode(await res.readAsString())
          as Map<String, dynamic>)['entries'] as List;
      expect(entries.length, 3);
      expect((entries.last as Map)['message'], 'm9');
    });

    test('/logs returns empty entries when no sink is configured', () async {
      final bare = BridgeRouter(
        screenshotService: ScreenshotService(),
        widgetTreeService: WidgetTreeService(),
        gestureService: GestureService(),
        appInfoService: AppInfoService(),
        findService: FindService(),
      );
      final res =
          await bare.handler(Request('GET', Uri.parse('http://x:8888/logs')));
      expect(res.statusCode, 200);
      final entries = (jsonDecode(await res.readAsString())
          as Map<String, dynamic>)['entries'] as List;
      expect(entries, isEmpty);
    });

    test('/network returns entries the recorder has accumulated', () async {
      router.network!.record(
        method: 'GET',
        url: 'https://api.example.com/x',
        status: 200,
        durationMs: 5,
      );
      final res = await router
          .handler(Request('GET', Uri.parse('http://x:8888/network')));
      final entries = (jsonDecode(await res.readAsString())
          as Map<String, dynamic>)['entries'] as List;
      expect(entries.length, 1);
      expect((entries.first as Map)['url'], 'https://api.example.com/x');
    });

    test('/info includes the active DevTools port when available', () async {
      final withDevTools = BridgeRouter(
        screenshotService: ScreenshotService(),
        widgetTreeService: WidgetTreeService(),
        gestureService: GestureService(),
        appInfoService: _FakeAppInfoService(),
        findService: FindService(),
        devToolsPortProvider: () => 4567,
      );

      final res = await withDevTools
          .handler(Request('GET', Uri.parse('http://x:8888/info')));
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;

      expect(body['devTools'], {
        'enabled': true,
        'port': 4567,
      });
    });

    test('/pick returns 400 when x/y are missing', () async {
      final res =
          await router.handler(Request('GET', Uri.parse('http://x:8888/pick')));
      expect(res.statusCode, 400);
    });
  });

  group('TurboBridge end-to-end with DevTools', () {
    test('boots both servers and surfaces the request log', () async {
      final bridge = await TurboBridge.start(
        config: const BridgeConfig(
          port: 0,
          enableDevTools: true,
          devToolsPort: 0,
        ),
      );

      try {
        expect(bridge.port, isNotNull);
        expect(bridge.devToolsPort, isNotNull);

        // Hit the JSON-API port — should be recorded in the log.
        final client = HttpClient();
        final infoReq = await client
            .getUrl(Uri.parse('http://127.0.0.1:${bridge.port}/info'));
        final infoResp = await infoReq.close();
        expect(infoResp.statusCode, 200);
        final infoBody = jsonDecode(
          await infoResp.transform(utf8.decoder).join(),
        ) as Map<String, dynamic>;
        expect(infoBody['devTools'], {
          'enabled': true,
          'port': bridge.devToolsPort,
        });

        final req = await client
            .getUrl(Uri.parse('http://127.0.0.1:${bridge.port}/health'));
        final resp = await req.close();
        expect(resp.statusCode, 200);
        await resp.drain<void>();

        // Give the middleware microtask a chance to log.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bridge.requestLog.length, greaterThanOrEqualTo(1));

        // The DevTools log endpoint reflects the same data.
        final devReq = await client.getUrl(Uri.parse(
            'http://127.0.0.1:${bridge.devToolsPort}/api/devtools/requests'));
        final devResp = await devReq.close();
        final body =
            jsonDecode(await devResp.transform(utf8.decoder).join()) as Map;
        expect((body['entries'] as List), isNotEmpty);

        // The DevTools UI shell is served from /.
        final indexReq = await client
            .getUrl(Uri.parse('http://127.0.0.1:${bridge.devToolsPort}/'));
        final indexResp = await indexReq.close();
        expect(indexResp.statusCode, 200);
        expect(
            indexResp.headers.value('content-type'), startsWith('text/html'));
        final indexBody = await indexResp.transform(utf8.decoder).join();
        expect(indexBody, contains('Turbo Bridge'));
        // The bundle now inlines its JS — there should be a <script>
        // block in the shell.
        expect(indexBody, contains('<script'));

        client.close(force: true);
      } finally {
        await bridge.stop();
      }
    }, tags: ['integration']);
  });
}
