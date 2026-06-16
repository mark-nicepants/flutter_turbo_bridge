import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// Hide the http `Request`/`Response` so they don't clash with shelf's
// same-named types used by the router tests below.
import 'package:http_interceptor/http_interceptor.dart' hide Request, Response;
import 'package:shelf/shelf.dart';
import 'package:turbo_bridge/src/devtools/devtools_api.dart';
import 'package:turbo_bridge/src/devtools/event_bus.dart';
import 'package:turbo_bridge/src/devtools/request_log.dart';
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
        remoteAddress: '127.0.0.1',
      );
      final b = log.record(
        method: 'POST',
        path: '/tap',
        query: null,
        status: 200,
        durationMs: 3,
        remoteAddress: '127.0.0.1',
      );
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
          remoteAddress: null,
        );
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
        remoteAddress: '10.0.0.5',
      );
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

    test('marks body as truncated past the 512 KB cap', () {
      final log = RequestLog();
      final big = List<int>.filled(600 * 1024, 0x41); // 'A' * 600k
      final entry = log.record(
        method: 'GET',
        path: '/big',
        query: null,
        status: 200,
        durationMs: 1,
        remoteAddress: null,
        responseBodyBytes: big,
      );
      expect(entry.responseBodySize, 600 * 1024);
      expect(entry.responseBodyTruncated, isTrue);
      expect(entry.responseBody!.length, 512 * 1024);
    });

    test('keeps bodies up to the cap intact', () {
      final log = RequestLog();
      final body = List<int>.filled(64 * 1024, 0x41); // 64k, under the cap
      final entry = log.record(
        method: 'GET',
        path: '/medium',
        query: null,
        status: 200,
        durationMs: 1,
        remoteAddress: null,
        responseBodyBytes: body,
      );
      expect(entry.responseBodyTruncated, isFalse);
      expect(entry.responseBody!.length, 64 * 1024);
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

  group('LogEntry.toJson source location', () {
    test('passes the captured source URI through verbatim', () {
      // The app emits the raw frame URI (`package:…` or `file://…`); the
      // DevTools UI resolves `package:` URIs to file paths client-side.
      const pkgUri = 'package:my_app/foo.dart';
      final entry = LogEntry(
        id: 1,
        timestamp: DateTime.utc(2026),
        level: LogLevel.info,
        message: 'hi',
        sourceFile: pkgUri,
        sourceLine: 10,
        sourceColumn: 3,
      );

      final json = entry.toJson();
      expect(json['sourceFile'], pkgUri);
      expect(json['sourceLine'], 10);
      expect(json['sourceColumn'], 3);
    });
  });

  group('LogSink', () {
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

    test('start + fail can include response details', () {
      final bus = DevToolsEventBus();
      final net = NetworkLog(bus: bus);
      final inflight = net.start(method: 'POST', url: 'x');
      inflight.fail(
        Exception('bad request'),
        status: 400,
        responseHeaders: {'content-type': 'application/json'},
        responseBody: '{"error":"invalid"}',
      );
      final call = net.snapshot().single;
      expect(call.status, 400);
      expect(call.error, contains('bad request'));
      expect(call.responseHeaders, {'content-type': 'application/json'});
      expect(call.responseBody, '{"error":"invalid"}');
      expect(call.responseBodySize, '{"error":"invalid"}'.length);
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

    test('start surfaces an in-flight entry immediately', () async {
      final bus = DevToolsEventBus();
      final net = NetworkLog(bus: bus);
      final events = <Map<String, dynamic>>[];
      final sub = bus.stream.listen((e) => events.add(e.payload));

      final inflight = net.start(method: 'GET', url: 'https://x/slow');

      // Visible on the timeline before the response arrives.
      final pending = net.snapshot().single;
      expect(pending.inFlight, isTrue);
      expect(pending.status, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(events.single['inFlight'], isTrue);

      inflight.complete(status: 200);
      await Future<void>.delayed(Duration.zero);

      // Same entry, now finalized — not a second row.
      expect(net.snapshot(), hasLength(1));
      final done = net.snapshot().single;
      expect(done.inFlight, isFalse);
      expect(done.status, 200);

      // Two emissions for one call: start (in-flight) then complete.
      expect(events, hasLength(2));
      expect(events[0]['inFlight'], isTrue);
      expect(events[1]['inFlight'], isFalse);
      expect(events[1]['status'], 200);

      await sub.cancel();
      await bus.close();
    });

    test('complete after the entry is evicted is a silent no-op', () {
      final bus = DevToolsEventBus();
      final net = NetworkLog(bus: bus, capacity: 1);
      final inflight = net.start(method: 'GET', url: 'a');
      // Push past the cap so the in-flight entry is evicted.
      net.record(method: 'GET', url: 'b');
      expect(net.snapshot().map((e) => e.url), ['b']);

      // Must not throw and must not resurrect the evicted entry.
      expect(() => inflight.complete(status: 200), returnsNormally);
      expect(net.snapshot().map((e) => e.url), ['b']);
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

  group('TurboBridgeHttpInterceptor', () {
    tearDown(() async {
      await TurboBridge.instance.stop();
    });

    InterceptedClient buildClient({
      required Future<StreamedResponse> Function(BaseRequest) onSend,
      bool captureResponseBody = true,
    }) {
      return InterceptedClient.build(
        interceptors: [
          TurboBridgeHttpInterceptor(captureResponseBody: captureResponseBody),
        ],
        client: _StubClient(onSend),
      );
    }

    test(
      'records a successful exchange with request + response bodies',
      () async {
        final bridge = TurboBridge.createForTest();
        final client = buildClient(
          onSend: (request) async => StreamedResponse(
            Stream.value(utf8.encode('{"ok":true}')),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        );

        final resp = await client.post(
          Uri.parse('https://api.example.com/items'),
          body: '{"name":"a"}',
        );

        // Caller sees an untouched response.
        expect(resp.statusCode, 200);
        expect(resp.body, '{"ok":true}');

        final calls = bridge.network.snapshot();
        expect(calls.length, 1);
        final call = calls.single;
        expect(call.method, 'POST');
        expect(call.url, 'https://api.example.com/items');
        expect(call.status, 200);
        expect(call.requestBody, '{"name":"a"}');
        expect(call.responseBody, '{"ok":true}');
        expect(call.responseBodySize, '{"ok":true}'.length);
      },
    );

    test('records 4xx/5xx exchanges (no error hook needed)', () async {
      final bridge = TurboBridge.createForTest();
      final client = buildClient(
        onSend: (request) async => StreamedResponse(
          Stream.value(utf8.encode('nope')),
          503,
          request: request,
        ),
      );

      await client.get(Uri.parse('https://api.example.com/down'));

      final call = bridge.network.snapshot().single;
      expect(call.status, 503);
      expect(call.responseBody, 'nope');
    });

    test('captureResponseBody: false records metadata only', () async {
      final bridge = TurboBridge.createForTest();
      final client = buildClient(
        captureResponseBody: false,
        onSend: (request) async => StreamedResponse(
          Stream.value(utf8.encode('{"ok":true}')),
          200,
          contentLength: 11,
          request: request,
        ),
      );

      final resp = await client.get(Uri.parse('https://api.example.com/items'));
      // Stream is left untouched for the caller to drain.
      expect(resp.body, '{"ok":true}');

      final call = bridge.network.snapshot().single;
      expect(call.status, 200);
      expect(call.responseBody, isNull);
      expect(call.responseBodySize, 11);
    });

    test('retryPolicy records send failures without adding retries', () async {
      final bridge = TurboBridge.createForTest();
      final interceptor = TurboBridgeHttpInterceptor();
      var attempts = 0;
      final client = InterceptedClient.build(
        interceptors: [interceptor],
        retryPolicy: interceptor.retryPolicy(),
        client: _StubClient((request) async {
          attempts++;
          throw const SocketException('connection refused');
        }),
      );

      await expectLater(
        client.get(Uri.parse('https://api.example.com/down')),
        throwsA(isA<SocketException>()),
      );

      // Logging policy declines to retry, so the send ran exactly once.
      expect(attempts, 1);
      final call = bridge.network.snapshot().single;
      expect(call.status, isNull);
      expect(call.error, contains('connection refused'));
      expect(call.url, 'https://api.example.com/down');
    });

    test(
      'retryPolicy preserves a wrapped policy and logs each failed attempt',
      () async {
        final bridge = TurboBridge.createForTest();
        final interceptor = TurboBridgeHttpInterceptor();
        var attempts = 0;
        final client = InterceptedClient.build(
          interceptors: [interceptor],
          retryPolicy: interceptor.retryPolicy(wrapping: _RetryOncePolicy()),
          client: _StubClient((request) async {
            attempts++;
            if (attempts == 1) {
              throw const SocketException('connection refused');
            }
            return StreamedResponse(
              Stream.value(utf8.encode('{"ok":true}')),
              200,
              request: request,
            );
          }),
        );

        final resp = await client.get(
          Uri.parse('https://api.example.com/items'),
        );
        expect(resp.statusCode, 200);
        expect(attempts, 2); // inner policy retried once

        // First attempt logged as a failure, second as a success.
        final calls = bridge.network.snapshot();
        expect(calls.length, 2);
        expect(calls.first.error, contains('connection refused'));
        expect(calls.first.status, isNull);
        expect(calls.last.status, 200);
        expect(calls.last.responseBody, '{"ok":true}');
      },
    );

    test('honors the urlFor override', () async {
      final bridge = TurboBridge.createForTest();
      final client = InterceptedClient.build(
        interceptors: [
          TurboBridgeHttpInterceptor(
            urlFor: (r) => r.url.removeFragment().replace(query: '').path,
          ),
        ],
        client: _StubClient(
          (request) async =>
              StreamedResponse(const Stream.empty(), 200, request: request),
        ),
      );

      await client.get(Uri.parse('https://api.example.com/items?token=secret'));

      // The recorded URL came from urlFor, not request.url (which had the
      // secret query string).
      expect(bridge.network.snapshot().single.url, '/items');
    });

    test(
      'survives a retry-on-response without "Can\'t finalize" (issue repro)',
      () async {
        final bridge = TurboBridge.createForTest();
        // Inner client that finalizes the request like a real HTTP client —
        // returns 401 on the first attempt, 200 on the retry.
        final inner = _FinalizingClient((attempt) => attempt == 1 ? 401 : 200);
        final client = InterceptedClient.build(
          interceptors: [TurboBridgeHttpInterceptor()],
          client: inner,
          retryPolicy: _RetryOn401Policy(),
        );

        // Before the fix this threw "Bad state: Can't finalize a finalized
        // Request" on the second attempt (http_interceptor re-sends the same
        // request object).
        final resp = await client.get(
          Uri.parse('https://api.example.com/clients/paged?page=0&pageSize=20'),
        );

        expect(inner.attempts, 2);
        expect(resp.statusCode, 200);
        // Both attempts were recorded on the timeline.
        final calls = bridge.network.snapshot();
        expect(calls.length, 2);
        expect(calls.every((c) => c.method == 'GET'), isTrue);
      },
    );
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

  group('DevToolsApi', () {
    late RequestLog log;
    late DevToolsEventBus bus;
    late DevToolsApi api;

    setUp(() {
      log = RequestLog();
      bus = DevToolsEventBus();
      api = DevToolsApi(
        eventBus: bus,
        requestLog: log,
        logs: LogSink(bus: bus),
        network: NetworkLog(bus: bus),
        navigation: NavigationLog(bus: bus),
      );
    });

    tearDown(() async {
      await bus.close();
    });

    test('handles() owns devtools/* and events paths', () {
      expect(DevToolsApi.handles('events'), isTrue);
      expect(DevToolsApi.handles('devtools/logs'), isTrue);
      expect(DevToolsApi.handles('devtools/network/5'), isTrue);
      expect(DevToolsApi.handles('health'), isFalse);
      expect(DevToolsApi.handles('tap'), isFalse);
    });

    test('devtools/requests returns the current log snapshot', () async {
      log.record(
        method: 'GET',
        path: '/health',
        query: null,
        status: 200,
        durationMs: 1,
        remoteAddress: '127.0.0.1',
      );
      final res = await api.handler(
        Request('GET', Uri.parse('http://x:8888/devtools/requests')),
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect((body['entries'] as List).length, 1);
      expect((body['entries'] as List).first['path'], '/health');
    });

    test('devtools/logs returns app-pushed log entries', () async {
      final sink = LogSink(bus: bus);
      api = DevToolsApi(
        eventBus: bus,
        requestLog: log,
        logs: sink,
        network: NetworkLog(bus: bus),
        navigation: NavigationLog(bus: bus),
      );
      sink.info('hello world', category: 'auth');
      sink.error('boom', category: 'net', error: Exception('nope'));

      final res = await api.handler(
        Request('GET', Uri.parse('http://x:8888/devtools/logs')),
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      final entries = body['entries'] as List;
      expect(entries.length, 2);
      expect(entries[0]['message'], 'hello world');
      expect(entries[1]['level'], 'error');
    });

    test('devtools/network returns app-pushed network calls', () async {
      final net = NetworkLog(bus: bus);
      api = DevToolsApi(
        eventBus: bus,
        requestLog: log,
        logs: LogSink(bus: bus),
        network: net,
        navigation: NavigationLog(bus: bus),
      );
      final call = net.record(
        method: 'GET',
        url: 'https://api.example.com/users/1',
        status: 200,
        durationMs: 42,
        responseBody: '{"id":1}',
      );

      final list = await api.handler(
        Request('GET', Uri.parse('http://x:8888/devtools/network')),
      );
      final entries =
          (jsonDecode(await list.readAsString()) as Map)['entries'] as List;
      expect(entries.length, 1);
      expect(entries.first['url'], 'https://api.example.com/users/1');

      final detail = await api.handler(
        Request('GET', Uri.parse('http://x:8888/devtools/network/${call.id}')),
      );
      final d = jsonDecode(await detail.readAsString()) as Map<String, dynamic>;
      expect(d['responseBody'], '{"id":1}');
    });

    test('devtools/requests/:id returns full detail with bodies', () async {
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

      final res = await api.handler(
        Request(
          'GET',
          Uri.parse('http://x:8888/devtools/requests/${entry.id}'),
        ),
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body['requestBody'], '{"x":1,"y":2}');
      expect(body['responseBody'], '{"success":true}');
      expect(
        (body['responseHeaders'] as Map)['content-type'],
        'application/json',
      );
    });

    test('events opens an SSE stream and pushes emitted events', () async {
      final res = await api.handler(
        Request('GET', Uri.parse('http://x:8888/events')),
      );
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
      final res = await router.handler(
        Request('GET', Uri.parse('http://x:8888/logs')),
      );
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
      final res = await router.handler(
        Request('GET', Uri.parse('http://x:8888/logs?level=warn')),
      );
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      final entries = body['entries'] as List;
      expect(entries.length, 1);
      expect((entries.first as Map)['level'], 'error');
    });

    test('/logs honours limit (returns the tail)', () async {
      for (var i = 0; i < 10; i++) {
        router.logs!.info('m$i');
      }
      final res = await router.handler(
        Request('GET', Uri.parse('http://x:8888/logs?limit=3')),
      );
      final entries =
          (jsonDecode(await res.readAsString())
                  as Map<String, dynamic>)['entries']
              as List;
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
      final res = await bare.handler(
        Request('GET', Uri.parse('http://x:8888/logs')),
      );
      expect(res.statusCode, 200);
      final entries =
          (jsonDecode(await res.readAsString())
                  as Map<String, dynamic>)['entries']
              as List;
      expect(entries, isEmpty);
    });

    test('/network returns entries the recorder has accumulated', () async {
      router.network!.record(
        method: 'GET',
        url: 'https://api.example.com/x',
        status: 200,
        durationMs: 5,
      );
      final res = await router.handler(
        Request('GET', Uri.parse('http://x:8888/network')),
      );
      final entries =
          (jsonDecode(await res.readAsString())
                  as Map<String, dynamic>)['entries']
              as List;
      expect(entries.length, 1);
      expect((entries.first as Map)['url'], 'https://api.example.com/x');
    });

    test('/info reports DevTools enabled when configured', () async {
      final withDevTools = BridgeRouter(
        screenshotService: ScreenshotService(),
        widgetTreeService: WidgetTreeService(),
        gestureService: GestureService(),
        appInfoService: _FakeAppInfoService(),
        findService: FindService(),
        devToolsEnabled: true,
      );

      final res = await withDevTools.handler(
        Request('GET', Uri.parse('http://x:8888/info')),
      );
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;

      expect(body['devTools'], {'enabled': true});
    });

    test('/info reports DevTools disabled by default', () async {
      final withoutDevTools = BridgeRouter(
        screenshotService: ScreenshotService(),
        widgetTreeService: WidgetTreeService(),
        gestureService: GestureService(),
        appInfoService: _FakeAppInfoService(),
        findService: FindService(),
      );
      final res = await withoutDevTools.handler(
        Request('GET', Uri.parse('http://x:8888/info')),
      );
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body['devTools'], {'enabled': false});
    });

    test('/pick returns 400 when x/y are missing', () async {
      final res = await router.handler(
        Request('GET', Uri.parse('http://x:8888/pick')),
      );
      expect(res.statusCode, 400);
    });
  });

  group('TurboBridge end-to-end with DevTools', () {
    test(
      'serves API + DevTools data on one port and logs requests',
      () async {
        final bridge = await TurboBridge.start(
          config: const BridgeConfig(port: 0, enableDevTools: true),
        );

        try {
          expect(bridge.port, isNotNull);

          // Hit the JSON-API port — should be recorded in the log.
          final client = HttpClient();
          final infoReq = await client.getUrl(
            Uri.parse('http://127.0.0.1:${bridge.port}/info'),
          );
          final infoResp = await infoReq.close();
          expect(infoResp.statusCode, 200);
          final infoBody =
              jsonDecode(await infoResp.transform(utf8.decoder).join())
                  as Map<String, dynamic>;
          expect(infoBody['devTools'], {'enabled': true});

          final req = await client.getUrl(
            Uri.parse('http://127.0.0.1:${bridge.port}/health'),
          );
          final resp = await req.close();
          expect(resp.statusCode, 200);
          await resp.drain<void>();

          // Give the middleware microtask a chance to log.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(bridge.requestLog.length, greaterThanOrEqualTo(1));

          // The DevTools data endpoints live on the same port now.
          final devReq = await client.getUrl(
            Uri.parse('http://127.0.0.1:${bridge.port}/devtools/requests'),
          );
          final devResp = await devReq.close();
          final body =
              jsonDecode(await devResp.transform(utf8.decoder).join()) as Map;
          expect((body['entries'] as List), isNotEmpty);

          // The SSE stream is available on the same port.
          final eventsReq = await client.getUrl(
            Uri.parse('http://127.0.0.1:${bridge.port}/events'),
          );
          final eventsResp = await eventsReq.close();
          expect(eventsResp.statusCode, 200);
          expect(
            eventsResp.headers.value('content-type'),
            startsWith('text/event-stream'),
          );
          eventsReq.abort();

          client.close(force: true);
        } finally {
          await bridge.stop();
        }
      },
      tags: ['integration'],
    );
  });
}

/// Inner [Client] for `InterceptedClient` whose `send` is supplied by the
/// test, so no real network call is made.
class _StubClient extends BaseClient {
  _StubClient(this._onSend);

  final Future<StreamedResponse> Function(BaseRequest) _onSend;

  @override
  Future<StreamedResponse> send(BaseRequest request) => _onSend(request);
}

/// Inner [Client] that *finalizes* the request like a real HTTP client (so
/// re-sending the same request throws), returning a status chosen per attempt.
class _FinalizingClient extends BaseClient {
  _FinalizingClient(this._statusFor);

  final int Function(int attempt) _statusFor;
  int attempts = 0;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    attempts++;
    // Mimic a real client: finalizing a request twice throws.
    await request.finalize().toBytes();
    return StreamedResponse(
      Stream.value(utf8.encode('{"ok":true}')),
      _statusFor(attempts),
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

/// [RetryPolicy] that retries once when the response is a 401 — mirrors a
/// token-refresh policy.
class _RetryOn401Policy implements RetryPolicy {
  @override
  int get maxRetryAttempts => 1;

  @override
  bool shouldAttemptRetryOnException(Exception reason, BaseRequest request) =>
      false;

  @override
  bool shouldAttemptRetryOnResponse(BaseResponse response) =>
      response.statusCode == 401;

  @override
  Duration delayRetryAttemptOnException({required int retryAttempt}) =>
      Duration.zero;

  @override
  Duration delayRetryAttemptOnResponse({required int retryAttempt}) =>
      Duration.zero;
}

/// Minimal [RetryPolicy] that retries once on any exception — used to check
/// that `TurboBridgeHttpInterceptor.retryPolicy(wrapping: ...)` keeps the
/// wrapped policy's behavior.
class _RetryOncePolicy implements RetryPolicy {
  @override
  int get maxRetryAttempts => 1;

  @override
  bool shouldAttemptRetryOnException(Exception reason, BaseRequest request) =>
      true;

  @override
  bool shouldAttemptRetryOnResponse(BaseResponse response) => false;

  @override
  Duration delayRetryAttemptOnException({required int retryAttempt}) =>
      Duration.zero;

  @override
  Duration delayRetryAttemptOnResponse({required int retryAttempt}) =>
      Duration.zero;
}
