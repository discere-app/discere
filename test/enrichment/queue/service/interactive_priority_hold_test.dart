import 'package:discere/enrichment/queue/service/interactive_priority_hold.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers InteractivePriorityHold — the nesting rules behind "pause the
/// enrichment queue while something interactive is on screen". Only the
/// edges may act: pausing twice must not pause twice, and one of two
/// overlapping review sessions ending must not resume the queue.

void main() {
  test('starts out holding nothing', () {
    expect(InteractivePriorityHold().isActive, isFalse);
  });

  test('the first hold is the one that has to stop the queue', () {
    final hold = InteractivePriorityHold();

    expect(hold.acquire(), isTrue);
    expect(hold.isActive, isTrue);
  });

  test('a nested hold does not stop the queue again', () {
    final hold = InteractivePriorityHold()..acquire();

    expect(hold.acquire(), isFalse);
    expect(hold.holdCount, 2);
  });

  test('giving back one of two holds keeps the queue stopped', () {
    final hold = InteractivePriorityHold()
      ..acquire()
      ..acquire();

    expect(hold.release(), isFalse);
    expect(hold.isActive, isTrue);
  });

  test('the last hold is the one that lets the queue run again', () {
    final hold = InteractivePriorityHold()
      ..acquire()
      ..acquire();
    hold.release();

    expect(hold.release(), isTrue);
    expect(hold.isActive, isFalse);
  });

  test('releasing what was never held changes nothing', () {
    final hold = InteractivePriorityHold();

    expect(hold.release(), isFalse);
    expect(hold.holdCount, 0);

    // And the next real hold still works: an unbalanced release must not
    // leave the counter below zero, where the following acquire would look
    // like a nested one and never stop the queue.
    expect(hold.acquire(), isTrue);
  });

  test('a hold can be taken again after the last one was given back', () {
    final hold = InteractivePriorityHold()..acquire();
    hold.release();

    expect(hold.acquire(), isTrue);
  });
}
