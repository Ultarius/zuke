import 'package:flutter_test/flutter_test.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

void main() {
  test('single keys compare by binding identity', () {
    expect(
      const FlutterBindingKey.single('todo.add'),
      equals(const FlutterBindingKey.single('todo.add')),
    );
    expect(
      const FlutterBindingKey.single('todo.add'),
      isNot(equals(const FlutterBindingKey.collection('todo.add'))),
    );
  });

  test('collection item keys are unique and remain in their family', () {
    const tasks = FlutterBindingKey.collection('todo.taskText');
    const states = FlutterBindingKey.collection('todo.taskState');
    final first = tasks.instance('first');
    final second = tasks.instance('second');

    expect(first, isNot(equals(second)));
    expect(tasks.matches(first), isTrue);
    expect(tasks.matches(second), isTrue);
    expect(states.matches(first), isFalse);
  });

  test('single keys cannot create collection instances', () {
    expect(
      () => const FlutterBindingKey.single('todo.add').instance('first'),
      throwsStateError,
    );
  });

  test('typed instances remain stable through list reordering and removal', () {
    const family = FlutterBindingKey.collection('todo.taskText');
    final first = family.instance('first');
    final second = family.instance('second');
    final reordered = [second, first];

    expect(reordered, containsAll([first, second]));
    expect(reordered.where(family.matches), hasLength(2));
    expect([second].where(family.matches), contains(second));
  });

  test('empty typed binding IDs are rejected in checked mode', () {
    expect(() => FlutterBindingKey.single(''), throwsAssertionError);
    expect(() => FlutterBindingInstanceKey('', 'item'), throwsAssertionError);
  });
}
