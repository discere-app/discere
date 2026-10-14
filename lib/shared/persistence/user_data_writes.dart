import 'dart:async';

/// Keeps count of the write sequences into the user database that are under
/// way, so the in-app restart can wait for them before it closes the
/// database.
///
/// A sequence is anything that writes in more than one step: rows across
/// several tables, a write that depends on a read before it, a loop over
/// decks. Closing the database between two of its steps would leave the
/// first written and the rest failing on a closed database. A single
/// statement needs no entry here — the restart waits for every statement
/// already handed to the database anyway.
///
/// Never wrap anything that waits for the user: a dialog torn down by the
/// restart never answers, and [drained] would wait for it forever.
///
/// One instance per bootstrap run, injected into the services that own such
/// sequences and provided to the pages that chain several of them.
class UserDataWrites {
  int _running = 0;
  Completer<void>? _idle;

  /// Runs [sequence], counted as under way until it completes or fails.
  Future<T> run<T>(Future<T> Function() sequence) async {
    _running++;
    try {
      return await sequence();
    } finally {
      _running--;
      if (_running == 0) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  /// Completes once no sequence is under way — at once if none is.
  Future<void> drained() {
    if (_running == 0) return Future<void>.value();
    return (_idle ??= Completer<void>()).future;
  }
}
