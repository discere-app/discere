import 'dart:async';

import 'package:discere/enrichment/service/deck_membership_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs sections one after another, in call order', () async {
    final lock = DeckMembershipLock();
    final events = <String>[];
    final releaseFirst = Completer<void>();

    final first = lock.run(() async {
      events.add('first start');
      await releaseFirst.future;
      events.add('first end');
    });
    final second = lock.run(() async => events.add('second'));
    final third = lock.run(() async => events.add('third'));
    await pumpEventQueue();
    expect(events, ['first start']);

    releaseFirst.complete();
    await Future.wait([first, second, third]);

    expect(events, ['first start', 'first end', 'second', 'third']);
  });

  test('a failing section reaches its caller and frees the lock', () async {
    final lock = DeckMembershipLock();

    final failing = lock.run<void>(() async => throw StateError('failed'));
    final next = lock
        .run(() async => 'ran')
        .timeout(const Duration(seconds: 1), onTimeout: () => 'still locked');

    await expectLater(failing, throwsStateError);
    expect(await next, 'ran');
  });
}
