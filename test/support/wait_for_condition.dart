import 'dart:async';

import 'package:flutter/foundation.dart';

/// Waits until [predicate] holds.
///
/// Two things are deliberately separate here, because conflating them is what
/// made the old version of this flaky:
///
/// **How it wakes up.** When a [signal] is given — the service under test is
/// usually a [ChangeNotifier] — the predicate is re-checked on every
/// notification. That is the moment the condition can actually have changed,
/// so waiting is as fast as the code under test and does not depend on how
/// busy the machine is. The slow poll underneath is a backstop for conditions
/// no notification covers, such as a mock recording a call.
///
/// **When it gives up.** [timeout] exists to turn a hang into a failing test,
/// nothing more. It is deliberately generous: a tight bound reads as a
/// performance assertion, and on a loaded machine — a CI runner with parallel
/// jobs, say — it fails for reasons that have nothing to do with the code.
/// A test that is actually broken still fails, it just takes longer to say so.
///
/// [description] is what the failure message says was being waited for. The
/// old message named nothing, so every occurrence started its diagnosis from
/// scratch.
Future<void> waitForCondition(
  bool Function() predicate, {
  required String description,
  Listenable? signal,
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (predicate()) return;

  final completer = Completer<void>();
  void check() {
    if (!completer.isCompleted && predicate()) completer.complete();
  }

  signal?.addListener(check);
  // Fires far less often than the old 10 ms loop: with a signal it is only
  // the backstop, and without one the condition is a side effect that no
  // amount of polling speed would reach sooner.
  final poll = Timer.periodic(const Duration(milliseconds: 25), (_) => check());

  try {
    await completer.future.timeout(
      timeout,
      onTimeout: () => throw StateError(
        'Timed out after ${timeout.inSeconds}s waiting for: $description',
      ),
    );
  } finally {
    poll.cancel();
    signal?.removeListener(check);
  }
}
