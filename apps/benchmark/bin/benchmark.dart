/// Flutter Turbo Bridge — Speed Benchmark
///
/// Measures latency of:
/// 1. Direct VM Service operations
/// 2. Turbo Bridge HTTP endpoints (in-app server)
///
/// Usage:
///   1. Start the target app: `cd ../target_app && flutter run --debug`
///   2. Copy the VM Service URI and run:
///      `dart run bin/benchmark.dart --vm-uri <ws://...> --bridge-port 8888`
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:turbo_bridge_client/turbo_bridge_client.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const int _defaultIterations = 50;

/// Target latencies in milliseconds (p95).
const Map<String, int> targets = {
  // VM Service direct
  'vm_service_connect': 500,
  'vm_get_vm': 30,
  'vm_get_isolate': 30,
  'vm_evaluate_simple': 50,
  'vm_evaluate_widget_tree': 100,
  'vm_service_extension_tree': 200,
  // Note: ext.flutter.inspector.screenshot requires inspector object IDs
  // (not 'root') and is for individual widget screenshots, not whole-screen.
  // Our bridge uses RenderRepaintBoundary.toImage() which is faster and simpler.
  // Turbo Bridge HTTP
  'bridge_health': 10,
  'bridge_screenshot': 50,
  'bridge_widget_tree': 40,
  'bridge_tap': 30,
  'bridge_app_info': 10,
  // Full AI loop (bridge screenshot + tree + tap)
  'bridge_full_loop': 100,
};

class BenchmarkResult {
  final String name;
  final List<int> durationsMs;
  final int targetMs;
  final bool success;
  final String? error;

  BenchmarkResult({
    required this.name,
    required this.durationsMs,
    required this.targetMs,
    this.success = true,
    this.error,
  });

  int get p50 => _percentile(50);
  int get p95 => _percentile(95);
  int get p99 => _percentile(99);
  int get min => durationsMs.isEmpty ? 0 : durationsMs.reduce((a, b) => a < b ? a : b);
  int get max => durationsMs.isEmpty ? 0 : durationsMs.reduce((a, b) => a > b ? a : b);
  double get mean => durationsMs.isEmpty ? 0 : durationsMs.reduce((a, b) => a + b) / durationsMs.length;

  bool get meetsTarget => success && p95 <= targetMs;

  int _percentile(int p) {
    if (durationsMs.isEmpty) return 0;
    final sorted = List<int>.from(durationsMs)..sort();
    final index = ((p / 100) * sorted.length).ceil() - 1;
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  @override
  String toString() {
    final status = meetsTarget ? '✓' : '✗';
    final statusColor = meetsTarget ? '\x1B[32m' : '\x1B[31m';
    const reset = '\x1B[0m';
    if (!success) {
      return '$statusColor✗$reset $name: FAILED — $error';
    }
    return '$statusColor$status$reset $name\n'
        '    p50=${p50}ms  p95=${p95}ms  p99=${p99}ms  '
        'min=${min}ms  max=${max}ms  mean=${mean.toStringAsFixed(1)}ms  '
        'target=${targetMs}ms';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'success': success,
        'meets_target': meetsTarget,
        'target_ms': targetMs,
        'p50_ms': p50,
        'p95_ms': p95,
        'p99_ms': p99,
        'min_ms': min,
        'max_ms': max,
        'mean_ms': mean,
        if (error != null) 'error': error,
      };
}

Future<List<int>> _bench(
  Future<void> Function() operation, {
  int count = _defaultIterations,
  int warmup = 3,
}) async {
  for (var i = 0; i < warmup; i++) {
    try {
      await operation();
    } catch (_) {}
  }

  final durations = <int>[];
  for (var i = 0; i < count; i++) {
    final sw = Stopwatch()..start();
    await operation();
    sw.stop();
    durations.add(sw.elapsedMilliseconds);
  }
  return durations;
}

BenchmarkResult _fail(String name, Object error) => BenchmarkResult(
      name: name,
      durationsMs: [],
      targetMs: targets[name] ?? 999,
      success: false,
      error: '$error',
    );

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('vm-uri', abbr: 'u', help: 'VM Service WebSocket URI')
    ..addOption('bridge-host', defaultsTo: '127.0.0.1', help: 'Turbo Bridge host')
    ..addOption('bridge-port', abbr: 'p', defaultsTo: '8888', help: 'Turbo Bridge port')
    ..addOption('iterations', abbr: 'n', defaultsTo: '$_defaultIterations')
    ..addFlag('vm-only', help: 'Only run VM Service benchmarks')
    ..addFlag('bridge-only', help: 'Only run Bridge benchmarks')
    ..addFlag('help', abbr: 'h', negatable: false);

  final parsed = parser.parse(args);

  if (parsed['help'] as bool) {
    print('Flutter Turbo Bridge — Speed Benchmark\n');
    print(parser.usage);
    exit(0);
  }

  final vmUri = parsed['vm-uri'] as String?;
  final bridgeHost = parsed['bridge-host'] as String;
  final bridgePort = int.parse(parsed['bridge-port'] as String);
  final iterCount = int.parse(parsed['iterations'] as String);
  final vmOnly = parsed['vm-only'] as bool;
  final bridgeOnly = parsed['bridge-only'] as bool;

  if (vmUri == null && !bridgeOnly) {
    print('Error: --vm-uri is required (unless using --bridge-only)\n');
    print(parser.usage);
    exit(1);
  }

  print('═══════════════════════════════════════════════════════════════');
  print(' Flutter Turbo Bridge — Speed Benchmark');
  if (vmUri != null) print(' VM Service URI: $vmUri');
  print(' Bridge: http://$bridgeHost:$bridgePort');
  print(' Iterations: $iterCount');
  print('═══════════════════════════════════════════════════════════════\n');

  final results = <BenchmarkResult>[];

  // ═══════════════════════════════════════════════════════════════════════
  //  VM SERVICE BENCHMARKS
  // ═══════════════════════════════════════════════════════════════════════
  if (!bridgeOnly && vmUri != null) {
    print('━━━ VM Service Direct ━━━\n');

    VmService? vmService;
    String? isolateId;

    // Connect
    try {
      final sw = Stopwatch()..start();
      vmService = await vmServiceConnectUri(vmUri);
      sw.stop();

      results.add(BenchmarkResult(
        name: 'vm_service_connect',
        durationsMs: [sw.elapsedMilliseconds],
        targetMs: targets['vm_service_connect']!,
      ));

      final vm = await vmService.getVM();
      isolateId = vm.isolates!.firstWhere((i) => !i.isSystemIsolate!).id!;
      print('Connected. Isolate: $isolateId\n');
    } catch (e) {
      print('Failed to connect to VM Service: $e\n');
      results.add(_fail('vm_service_connect', e));
    }

    if (vmService != null && isolateId != null) {
      // getVM
      print('  getVM()...');
      try {
        final d = await _bench(() => vmService!.getVM(), count: iterCount);
        results.add(BenchmarkResult(name: 'vm_get_vm', durationsMs: d, targetMs: targets['vm_get_vm']!));
      } catch (e) {
        results.add(_fail('vm_get_vm', e));
      }

      // getIsolate
      print('  getIsolate()...');
      try {
        final d = await _bench(() => vmService!.getIsolate(isolateId!), count: iterCount);
        results.add(BenchmarkResult(name: 'vm_get_isolate', durationsMs: d, targetMs: targets['vm_get_isolate']!));
      } catch (e) {
        results.add(_fail('vm_get_isolate', e));
      }

      // evaluate simple
      print('  evaluate("1+1")...');
      try {
        final isolate = await vmService.getIsolate(isolateId);
        final rootLib = isolate.rootLib?.id ?? isolateId;
        final d = await _bench(
          () => vmService!.evaluate(isolateId!, rootLib, '1 + 1'),
          count: iterCount,
        );
        results
            .add(BenchmarkResult(name: 'vm_evaluate_simple', durationsMs: d, targetMs: targets['vm_evaluate_simple']!));
      } catch (e) {
        results.add(_fail('vm_evaluate_simple', e));
      }

      // evaluate widget tree
      print('  evaluate(widgetTree)...');
      try {
        final isolate = await vmService.getIsolate(isolateId);
        final rootLib = isolate.rootLib?.id ?? isolateId;
        final d = await _bench(
          () => vmService!.evaluate(
            isolateId!,
            rootLib,
            'WidgetsBinding.instance.rootElement?.toStringDeep().length ?? 0',
          ),
          count: iterCount,
        );
        results.add(BenchmarkResult(
            name: 'vm_evaluate_widget_tree', durationsMs: d, targetMs: targets['vm_evaluate_widget_tree']!));
      } catch (e) {
        results.add(_fail('vm_evaluate_widget_tree', e));
      }

      // service extension: widget tree
      print('  ext.flutter.inspector.getRootWidgetTree...');
      try {
        final d = await _bench(
          () => vmService!.callServiceExtension(
            'ext.flutter.inspector.getRootWidgetTree',
            isolateId: isolateId,
            args: {
              'groupName': 'bench',
              'isSummaryTree': 'true',
              'withPreviews': 'false',
            },
          ),
          count: iterCount,
        );
        results.add(BenchmarkResult(
            name: 'vm_service_extension_tree', durationsMs: d, targetMs: targets['vm_service_extension_tree']!));
      } catch (e) {
        results.add(_fail('vm_service_extension_tree', e));
      }

      await vmService.dispose();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  TURBO BRIDGE BENCHMARKS
  // ═══════════════════════════════════════════════════════════════════════
  if (!vmOnly) {
    print('\n━━━ Turbo Bridge HTTP ━━━\n');

    final client = TurboBridgeClient(host: bridgeHost, port: bridgePort);

    // Health check
    print('  health...');
    try {
      final healthy = await client.isConnected();
      if (!healthy) {
        print('  Bridge not reachable at http://$bridgeHost:$bridgePort');
        print('  Skipping bridge benchmarks.\n');
      } else {
        final d = await _bench(() => client.isConnected(), count: iterCount);
        results.add(BenchmarkResult(name: 'bridge_health', durationsMs: d, targetMs: targets['bridge_health']!));

        // Screenshot
        print('  screenshot...');
        try {
          final d = await _bench(() => client.screenshot(), count: iterCount);
          results
              .add(BenchmarkResult(name: 'bridge_screenshot', durationsMs: d, targetMs: targets['bridge_screenshot']!));
        } catch (e) {
          results.add(_fail('bridge_screenshot', e));
        }

        // Widget tree
        print('  widgetTree...');
        try {
          final d = await _bench(() => client.widgetTree(), count: iterCount);
          results.add(
              BenchmarkResult(name: 'bridge_widget_tree', durationsMs: d, targetMs: targets['bridge_widget_tree']!));
        } catch (e) {
          results.add(_fail('bridge_widget_tree', e));
        }

        // Tap
        print('  tap...');
        try {
          final d = await _bench(() => client.tap(195, 400), count: iterCount);
          results.add(BenchmarkResult(name: 'bridge_tap', durationsMs: d, targetMs: targets['bridge_tap']!));
        } catch (e) {
          results.add(_fail('bridge_tap', e));
        }

        // App info
        print('  appInfo...');
        try {
          final d = await _bench(() => client.appInfo(), count: iterCount);
          results.add(BenchmarkResult(name: 'bridge_app_info', durationsMs: d, targetMs: targets['bridge_app_info']!));
        } catch (e) {
          results.add(_fail('bridge_app_info', e));
        }

        // Full AI loop: screenshot + tree + tap
        print('  full AI loop (screenshot + tree + tap)...');
        try {
          final d = await _bench(() async {
            await client.screenshot();
            await client.widgetTree();
            await client.tap(195, 400);
          }, count: iterCount);
          results
              .add(BenchmarkResult(name: 'bridge_full_loop', durationsMs: d, targetMs: targets['bridge_full_loop']!));
        } catch (e) {
          results.add(_fail('bridge_full_loop', e));
        }
      }
    } catch (e) {
      print('  Bridge health check failed: $e\n');
      results.add(_fail('bridge_health', e));
    }

    await client.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  RESULTS
  // ═══════════════════════════════════════════════════════════════════════
  print('\n═══════════════════════════════════════════════════════════════');
  print(' RESULTS');
  print('═══════════════════════════════════════════════════════════════\n');

  var passed = 0;
  var failed = 0;

  for (final result in results) {
    print(result);
    print('');
    if (result.meetsTarget) {
      passed++;
    } else {
      failed++;
    }
  }

  print('═══════════════════════════════════════════════════════════════');
  print(' Summary: $passed passed, $failed failed');
  print('═══════════════════════════════════════════════════════════════');

  // Write JSON results
  final jsonFile = File('benchmark_results.json');
  await jsonFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'timestamp': DateTime.now().toIso8601String(),
      'iterations': iterCount,
      'vm_service_uri': vmUri,
      'bridge_host': bridgeHost,
      'bridge_port': bridgePort,
      'results': results.map((r) => r.toJson()).toList(),
    }),
  );
  print('\nResults written to ${jsonFile.path}');

  exit(failed > 0 ? 1 : 0);
}
