import 'dart:io';

import 'package:test/test.dart';
import 'package:turbo_bridge_mcp/src/adb_forwarding.dart';

void main() {
  group('ensureBridgeReachable', () {
    test('forwards the bridge port when ADB is needed', () async {
      final commands = <String>[];
      var bridgeReachable = false;

      final session = await ensureBridgeReachable(
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
          return false;
        },
      );

      expect(session.bridgeForwarded, isTrue);
      expect(session.hasForwarding, isTrue);
      expect(session.summarySuffix, contains('8888'));

      await session.cleanup();

      expect(
        commands,
        containsAll([
          'adb devices',
          'adb forward tcp:8888 tcp:8888',
          'adb forward --remove tcp:8888',
        ]),
      );
    });

    test('does nothing when the bridge is already reachable', () async {
      final commands = <String>[];

      final session = await ensureBridgeReachable(
        host: 'localhost',
        bridgePort: 8888,
        processRunner: (executable, arguments) async {
          commands.add('$executable ${arguments.join(' ')}');
          throw UnimplementedError(arguments.join(' '));
        },
        reachabilityProbe: (_, port, path) async =>
            port == 8888 && path == '/health',
      );

      expect(session.bridgeForwarded, isFalse);
      expect(session.hasForwarding, isFalse);
      expect(session.summarySuffix, isEmpty);
      expect(commands, isEmpty);
    });
  });
}
