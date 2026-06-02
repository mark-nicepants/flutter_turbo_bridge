import 'dart:convert';
import 'dart:io';

/// Resolves `package:` URIs to absolute filesystem paths by reading the
/// project's `.dart_tool/package_config.json`.
///
/// This runs on the **host** (a standalone VM with filesystem access), so it
/// can do what the on-device Flutter app cannot: map `package:foo/bar.dart`
/// to its real source location — for *every* package, with no configuration.
/// The DevTools UI fetches the resulting map once and turns `package:` source
/// links into ⌘-clickable editor links.
class PackageResolver {
  PackageResolver(this.libDirs, {this.projectRoot});

  /// Package name -> absolute `lib/` directory (with a trailing separator).
  final Map<String, String> libDirs;

  /// The project root whose `package_config.json` was used, or null if none
  /// was found.
  final String? projectRoot;

  /// Build a resolver by locating the nearest `.dart_tool/package_config.json`
  /// walking upward from [startDir]. Returns an empty resolver (no error) when
  /// none is found or it can't be parsed.
  factory PackageResolver.forDirectory(String startDir) {
    final configFile = _findPackageConfig(startDir);
    if (configFile == null) return PackageResolver(const {});
    try {
      final json =
          jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
      final packages = (json['packages'] as List?) ?? const [];
      final base = configFile.uri; // file://.../.dart_tool/package_config.json
      final map = <String, String>{};
      for (final entry in packages) {
        if (entry is! Map) continue;
        final name = entry['name'];
        final rootUri = entry['rootUri'];
        final packageUri = entry['packageUri'] ?? 'lib/';
        if (name is! String || rootUri is! String || packageUri is! String) {
          continue;
        }
        // rootUri is relative to the package_config.json file's directory.
        final root =
            base.resolve(rootUri.endsWith('/') ? rootUri : '$rootUri/');
        final lib = root.resolve(packageUri);
        if (lib.scheme != 'file') continue;
        var path = lib.toFilePath();
        if (!path.endsWith(Platform.pathSeparator)) {
          path += Platform.pathSeparator;
        }
        map[name] = path;
      }
      return PackageResolver(
        map,
        projectRoot: configFile.parent.parent.path,
      );
    } catch (_) {
      return PackageResolver(const {});
    }
  }

  Map<String, dynamic> toJson() => {
        'projectRoot': projectRoot,
        'packages': libDirs,
      };

  static File? _findPackageConfig(String startDir) {
    var dir = Directory(startDir).absolute;
    while (true) {
      final file = File('${dir.path}/.dart_tool/package_config.json');
      if (file.existsSync()) return file;
      final parent = dir.parent;
      if (parent.path == dir.path) return null;
      dir = parent;
    }
  }
}
