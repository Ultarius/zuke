import 'package:flutter/foundation.dart';

/// Whether a logical binding maps to one widget or a family of widget
/// instances.
enum FlutterBindingKind {
  /// A key for one widget.
  single,

  /// A key family containing multiple widget instances.
  collection,
}

/// Stable logical Flutter key used by generated Zuke binding contracts.
///
/// A [single] key is mounted directly. A [collection] key is a family root;
/// list items mount [FlutterBindingInstanceKey] values created with
/// [instance]. This guarantees unique sibling keys without leaking a string
/// prefix convention into application code.
final class FlutterBindingKey extends LocalKey {
  /// Stable generated binding identifier.
  final String bindingId;

  /// Whether this key represents one widget or a collection.
  final FlutterBindingKind kind;

  /// Creates a key for one widget.
  const FlutterBindingKey.single(this.bindingId)
    : kind = FlutterBindingKind.single,
      assert(bindingId != '');

  /// Creates a key family for multiple widgets.
  const FlutterBindingKey.collection(this.bindingId)
    : kind = FlutterBindingKind.collection,
      assert(bindingId != '');

  /// Creates the key for one stable item in this collection binding.
  /// Creates a physical key for one collection item.
  FlutterBindingInstanceKey instance(Object instanceId) {
    if (kind != FlutterBindingKind.collection) {
      throw StateError(
        'Binding $bindingId is a single Flutter key and cannot create item instances.',
      );
    }
    return FlutterBindingInstanceKey(bindingId, instanceId);
  }

  /// Whether [candidate] belongs to this logical binding.
  /// Returns whether [candidate] belongs to this logical binding.
  bool matches(Key? candidate) => switch (candidate) {
    FlutterBindingKey(:final bindingId) => bindingId == this.bindingId,
    FlutterBindingInstanceKey(:final bindingId) =>
      kind == FlutterBindingKind.collection && bindingId == this.bindingId,
    _ => false,
  };

  @override
  bool operator ==(Object other) =>
      other is FlutterBindingKey &&
      other.bindingId == bindingId &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(bindingId, kind);

  @override
  String toString() => 'FlutterBindingKey.$kind($bindingId)';
}

/// Stable physical key for one item in a [FlutterBindingKey.collection].
final class FlutterBindingInstanceKey extends LocalKey {
  /// Stable logical binding identifier.
  final String bindingId;

  /// Application-owned item identifier.
  final Object instanceId;

  /// Creates a physical collection-item key.
  const FlutterBindingInstanceKey(this.bindingId, this.instanceId)
    : assert(bindingId != '');

  @override
  bool operator ==(Object other) =>
      other is FlutterBindingInstanceKey &&
      other.bindingId == bindingId &&
      other.instanceId == instanceId;

  @override
  int get hashCode => Object.hash(bindingId, instanceId);

  @override
  String toString() => 'FlutterBindingInstanceKey($bindingId, $instanceId)';
}
