import 'dart:collection';

import 'event_bus.dart';

/// One navigation event the app pushed into the bridge.
class NavigationEntry {
  final int id;
  final DateTime timestamp;
  final String route;
  final String? from;
  final String? action; // push, pop, replace, ...

  NavigationEntry({
    required this.id,
    required this.timestamp,
    required this.route,
    this.from,
    this.action,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'route': route,
        if (from != null) 'from': from,
        if (action != null) 'action': action,
      };
}

/// Ring buffer for navigation events.
///
/// Public API: `TurboBridge.instance.navigation.push('/cart')`.
/// Wire it from a `NavigatorObserver` so route changes appear in the
/// DevTools timeline next to logs and network calls.
class NavigationLog {
  final int capacity;
  final DevToolsEventBus _bus;
  final Queue<NavigationEntry> _entries = Queue<NavigationEntry>();
  int _nextId = 1;

  NavigationLog({required DevToolsEventBus bus, this.capacity = 200})
      : _bus = bus;

  int get length => _entries.length;

  List<NavigationEntry> snapshot() => List.unmodifiable(_entries);

  NavigationEntry record({
    required String route,
    String? from,
    String? action,
    DateTime? timestamp,
  }) {
    final entry = NavigationEntry(
      id: _nextId++,
      timestamp: (timestamp ?? DateTime.now()).toUtc(),
      route: route,
      from: from,
      action: action,
    );
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    _bus.emit(DevToolsEvent('navigation', entry.toJson()));
    return entry;
  }

  /// Convenience for the common "user navigated to" case.
  NavigationEntry push(String route, {String? from}) =>
      record(route: route, from: from, action: 'push');

  void clear() => _entries.clear();
}
