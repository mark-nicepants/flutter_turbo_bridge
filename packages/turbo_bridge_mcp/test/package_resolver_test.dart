import 'dart:io';

import 'package:test/test.dart';
import 'package:turbo_bridge_mcp/turbo_bridge_mcp.dart';

void main() {
  group('PackageResolver', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('pkg_resolver_test');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    void writeConfig(String body) {
      Directory('${tmp.path}/.dart_tool').createSync(recursive: true);
      File('${tmp.path}/.dart_tool/package_config.json')
          .writeAsStringSync(body);
    }

    test('maps package names to absolute lib dirs (relative + absolute roots)',
        () {
      writeConfig('''
{
  "configVersion": 2,
  "packages": [
    { "name": "my_app", "rootUri": "../", "packageUri": "lib/" },
    { "name": "some_dep",
      "rootUri": "file:///pub-cache/some_dep-1.0.0", "packageUri": "lib/" }
  ]
}
''');

      final sep = Platform.pathSeparator;
      final resolver = PackageResolver.forDirectory(tmp.path);
      expect(resolver.projectRoot, isNotNull);
      // Root package (relative "../") resolves to <project>/lib/.
      expect(resolver.libDirs['my_app'], '${tmp.path}${sep}lib$sep');
      // Absolute rootUri is honored verbatim.
      expect(
        resolver.libDirs['some_dep'],
        '${sep}pub-cache${sep}some_dep-1.0.0${sep}lib$sep',
      );
    });

    test('walks upward to find .dart_tool/package_config.json', () {
      writeConfig('''
{ "configVersion": 2,
  "packages": [ { "name": "my_app", "rootUri": "../", "packageUri": "lib/" } ] }
''');
      final nested = Directory('${tmp.path}/lib/src/deep')
        ..createSync(recursive: true);

      final resolver = PackageResolver.forDirectory(nested.path);
      expect(resolver.libDirs.containsKey('my_app'), isTrue);
    });

    test('returns an empty resolver when no package config exists', () {
      final resolver = PackageResolver.forDirectory(tmp.path);
      expect(resolver.projectRoot, isNull);
      expect(resolver.libDirs, isEmpty);
    });
  });
}
