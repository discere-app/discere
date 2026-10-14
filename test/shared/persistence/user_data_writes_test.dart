import 'dart:async';

import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UserDataWrites writes;

  setUp(() => writes = UserDataWrites());

  /// Whether [future] has completed after the pending microtasks ran.
  Future<bool> hasCompleted(Future<void> future) async {
    var completed = false;
    unawaited(future.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);
    return completed;
  }

  test('drained completes at once when nothing runs', () async {
    expect(await hasCompleted(writes.drained()), isTrue);
  });

  test('drained waits for a running sequence', () async {
    final release = Completer<void>();
    final sequence = writes.run(() => release.future);

    final drained = writes.drained();
    expect(await hasCompleted(drained), isFalse);

    release.complete();
    await sequence;
    expect(await hasCompleted(drained), isTrue);
  });

  test('drained waits for the last of several sequences', () async {
    final first = Completer<void>();
    final second = Completer<void>();
    final sequences = [
      writes.run(() => first.future),
      writes.run(() => second.future),
    ];

    final drained = writes.drained();
    first.complete();
    await sequences.first;
    expect(await hasCompleted(drained), isFalse);

    second.complete();
    await Future.wait(sequences);
    expect(await hasCompleted(drained), isTrue);
  });

  test('a failing sequence ends as well, and its error reaches the caller',
      () async {
    final release = Completer<void>();
    final sequence = writes.run<void>(() async {
      await release.future;
      throw StateError('write failed');
    });
    final drained = writes.drained();

    release.complete();
    await expectLater(sequence, throwsStateError);
    expect(await hasCompleted(drained), isTrue);
  });
}
