import 'dart:async';

/// Runs async tasks one at a time, in call order, on a private queue.
///
/// Each [run] call waits for the previous one to finish before starting its
/// own [action] — the underlying resource (e.g. a single DB connection) only
/// ever sees one query from this runner in flight at a time. If the caller's
/// [isAbandoned] check returns true once it's this task's turn, [action] is
/// skipped and [abandonedValue] is returned instead, so stale work queued
/// behind a still-running task doesn't execute pointlessly.
class SerializedTaskRunner {
  Future<void> _chain = Future.value();

  Future<T> run<T>(
    Future<T> Function() action, {
    required bool Function() isAbandoned,
    required T abandonedValue,
  }) {
    final completer = Completer<void>();
    final previousTask = _chain;
    _chain = completer.future;

    return (() async {
      await previousTask;
      try {
        if (isAbandoned()) return abandonedValue;
        return await action();
      } finally {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    })();
  }
}
