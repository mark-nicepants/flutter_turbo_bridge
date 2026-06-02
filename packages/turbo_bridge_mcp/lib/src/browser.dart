import 'dart:io';

/// Open [url] in the developer's default browser. Best-effort: failures are
/// swallowed (e.g. headless CI), since the URL is also printed.
Future<void> openInBrowser(String url) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
  } catch (_) {
    // Ignore — the caller prints the URL as a fallback.
  }
}
