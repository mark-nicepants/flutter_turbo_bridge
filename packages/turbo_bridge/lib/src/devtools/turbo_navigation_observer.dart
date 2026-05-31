import 'package:flutter/widgets.dart';

import '../bridge.dart';
import 'navigation_log.dart';

/// Forwards every Flutter route change into [TurboBridge.instance.navigation]
/// so DevTools can show pushes / pops / replaces on the timeline next to
/// logs and network calls.
///
/// Usage:
/// ```dart
/// MaterialApp(
///   navigatorObservers: [TurboNavigationObserver()],
///   ...
/// );
/// ```
///
/// Routes are identified by their `RouteSettings.name`. Anonymous routes
/// (no settings name) are reported as `<unnamed>` — set
/// `RouteSettings(name: ...)` on `MaterialPageRoute` or use named routes
/// to get readable timeline entries.
///
/// Safe to construct before `TurboBridge.start()` returns; observer
/// callbacks no-op if the singleton isn't initialized yet.
class TurboNavigationObserver extends NavigatorObserver {
  /// Optional override for naming routes. Defaults to
  /// `route.settings.name`, falling back to `<unnamed>`.
  final String Function(Route<dynamic> route)? nameFor;

  TurboNavigationObserver({this.nameFor});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record(route: route, from: previousRoute, action: 'push');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // After a pop the user is on previousRoute, so log THAT as the new
    // "current" route.
    _recordExplicit(
      route: previousRoute,
      from: route,
      action: 'pop',
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute == null) return;
    _record(route: newRoute, from: oldRoute, action: 'replace');
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _recordExplicit(
      route: previousRoute,
      from: route,
      action: 'remove',
    );
  }

  void _record({
    required Route<dynamic> route,
    Route<dynamic>? from,
    required String action,
  }) {
    _push(_name(route), from == null ? null : _name(from), action);
  }

  void _recordExplicit({
    required Route<dynamic>? route,
    Route<dynamic>? from,
    required String action,
  }) {
    if (route == null) return;
    _push(_name(route), from == null ? null : _name(from), action);
  }

  void _push(String to, String? from, String action) {
    final nav = _navOrNull();
    if (nav == null) return;
    nav.record(route: to, from: from, action: action);
  }

  NavigationLog? _navOrNull() {
    try {
      return TurboBridge.instance.navigation;
    } catch (_) {
      // Bridge not started yet — drop the event silently.
      return null;
    }
  }

  String _name(Route<dynamic> route) {
    if (nameFor != null) return nameFor!(route);
    return route.settings.name ?? '<unnamed>';
  }
}
