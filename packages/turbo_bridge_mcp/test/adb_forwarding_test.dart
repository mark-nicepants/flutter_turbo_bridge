import 'dart:io';

import 'package:test/test.dart';
import 'package:turbo_bridge_mcp/src/adb_forwarding.dart';

void main() {
  group('ensureBridgeAndDevToolsReachable', () {
    test('forwards bridge and DevTools ports when ADB is needed', () async {
      final commands = <String>[];
      var bridgeReachable = false;
      var devToolsReachable = false;

      final session = await ensureBridgeAndDevToolsReachable(
        host: 'localhost',
        bridgePort: 8888,
        processRunner: (executable, arguments) async {
          commands.add('$executable ${arguments.join(' ')}');
          if (arguments.length == 1 && arguments.first == 'devices') {
            return ProcessResult(
              1,
              0,
              'List of devices attached\nserial\tdevice\n',
              '',
            );
          }
          if (arguments.length == 3 && arguments[0] == 'forward') {
            if (arguments[1] == 'tcp:8888') {
              bridgeReachable = true;
            }
            if (arguments[1] == 'tcp:8889') {
              devToolsReachable = true;
            }
            return ProcessResult(1, 0, '', '');
          }
          if (arguments.length == 3 && arguments[1] == '--remove') {
            return ProcessResult(1, 0, '', '');
          }
          throw UnimplementedError(arguments.join(' '));
        },
        reachabilityProbe: (host, port, path) async {
          if (path == '/health') {
            return bridgeReachable;
          }
          if (path == '/') {
            return devToolsReachable;
          }
          return false;
        },
        bridgeInfoLoader: (_, __) async => {
          'devTools': {
            'enabled': true,
            'port': 8889,
          },
        },
      );

      expect(session.bridgeForwarded, isTrue);
      expect(session.devToolsForwarded, isTrue);
      expect(session.summarySuffix, contains('bridge=8888'));
      expect(session.summarySuffix, contains('devtools=8889'));

      await session.cleanup();

      expect(
        commands,
        containsAll([
          'adb devices',
          'adb forward tcp:8888 tcp:8888',
          'adb forward tcp:8889 tcp:8889',
          'adb forward --remove tcp:8889',
          'adb forward --remove tcp:8888',
        ]),
      );
    });

    test('forwards only DevTools when bridge is already reachable', () async {
      final commands = <String>[];
      var devToolsReachable = false;

      final session = await ensureBridgeAndDevToolsReachable(
        host: 'localhost',
        bridgePort: 8888,
        processRunner: (executable, arguments) async {
          commands.add('$executable ${arguments.join(' ')}');
          if (arguments.length == 1 && arguments.first == 'devices') {
            return ProcessResult(
              1,
              0,
              'List of devices attached\nserial\tdevice\n',
              '',
            );
          }
          if (arguments.length == 3 && arguments[0] == 'forward') {
            devToolsReachable = true;
            return ProcessResult(1, 0, '', '');
          }
          if (arguments.length == 3 && arguments[1] == '--remove') {
            return ProcessResult(1, 0, '', '');
          }
          throw UnimplementedError(arguments.join(' '));
        },
        reachabilityProbe: (_, port, path) async {
          if (port == 8888 && path == '/health') {
            return true;
          }
          if (port == 8889 && path == '/') {
            return devToolsReachable;
          }
          return false;
        },
        bridgeInfoLoader: (_, __) async => {
          'devTools': {
            'enabled': true,
            'port': 8889,
          },
        },
      );

      expect(session.bridgeForwarded, isFalse);
      expect(session.devToolsForwarded, isTrue);
      expect(commands, isNot(contains('adb forward tcp:8888 tcp:8888')));
      expect(commands, contains('adb forward tcp:8889 tcp:8889'));
    });
  });
}
