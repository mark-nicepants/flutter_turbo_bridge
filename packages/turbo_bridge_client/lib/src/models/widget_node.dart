/// A node in the widget tree returned by the bridge.
class WidgetNode {
  final String type;
  final String? key;
  final Map<String, double>? rect;
  final String? text;
  final List<WidgetNode> children;

  const WidgetNode({
    required this.type,
    this.key,
    this.rect,
    this.text,
    this.children = const [],
  });

  factory WidgetNode.fromJson(Map<String, dynamic> json) {
    return WidgetNode(
      type: json['type'] as String,
      key: json['key'] as String?,
      rect: json['rect'] != null
          ? (json['rect'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : null,
      text: json['text'] as String?,
      children: (json['children'] as List<dynamic>?)
              ?.map((c) => WidgetNode.fromJson(c as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  /// Find all nodes matching a predicate.
  List<WidgetNode> findAll(bool Function(WidgetNode) predicate) {
    final results = <WidgetNode>[];
    _findAll(predicate, results);
    return results;
  }

  void _findAll(bool Function(WidgetNode) predicate, List<WidgetNode> results) {
    if (predicate(this)) results.add(this);
    for (final child in children) {
      child._findAll(predicate, results);
    }
  }

  /// Find the first node matching a predicate, or null.
  WidgetNode? findFirst(bool Function(WidgetNode) predicate) {
    if (predicate(this)) return this;
    for (final child in children) {
      final found = child.findFirst(predicate);
      if (found != null) return found;
    }
    return null;
  }

  /// Find a node by its key value.
  WidgetNode? findByKey(String key) => findFirst((n) => n.key == key);

  /// Find all nodes containing the given text.
  List<WidgetNode> findByText(String text) =>
      findAll((n) => n.text != null && n.text!.contains(text));

  /// Find all nodes of a given widget type.
  List<WidgetNode> findByType(String type) => findAll((n) => n.type == type);

  /// Get the center point of this node's bounds, or null if no bounds.
  ({double x, double y})? get center {
    if (rect == null) return null;
    return (
      x: rect!['x']! + rect!['w']! / 2,
      y: rect!['y']! + rect!['h']! / 2,
    );
  }

  @override
  String toString() =>
      'WidgetNode($type${key != null ? ', key=$key' : ''}${text != null ? ', "$text"' : ''})';
}
