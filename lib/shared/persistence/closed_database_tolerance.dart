import 'package:discere/shared/util/logger.dart';
import 'package:sqflite/sqflite.dart';

/// Runs [operation], answering [whenClosed] instead if its database is
/// closed underneath it.
///
/// That is the one database failure the app expects. `main.dart` closes the
/// databases on `AppLifecycleState.detached` without waiting for work still
/// in flight, and integration tests delete the user database between tests
/// under calls the previous test never awaited. Either way there is nothing
/// left to read or write, so the work is dropped with a debug line.
///
/// Every other [DatabaseException] — a constraint, schema or data fault —
/// propagates unchanged, stack trace included, and is not logged here: a
/// caller that awaits the call decides what it means, and one that does not
/// leaves it to the uncaught-error log, which then records it exactly once.
Future<T> toleratingClosedDatabase<T>(
  ScopedLogger log,
  Future<T> Function() operation, {
  required T whenClosed,
}) async {
  try {
    return await operation();
  } on DatabaseException catch (error) {
    if (!error.isDatabaseClosedError()) rethrow;
    log.debug('Database closed underneath the call; work dropped');
    return whenClosed;
  }
}

/// [toleratingClosedDatabase] for an [operation] without a result. Returns
/// whether it ran to completion, so a caller that would follow up on it can
/// skip that too.
Future<bool> runToleratingClosedDatabase(
  ScopedLogger log,
  Future<void> Function() operation,
) {
  return toleratingClosedDatabase(log, () async {
    await operation();
    return true;
  }, whenClosed: false);
}

/// Runs [operation] for a caller that has to answer even when the database
/// cannot, falling back to [fallback] on any [DatabaseException].
///
/// A closed database is dropped as in [toleratingClosedDatabase]. Any other
/// failure is logged as a warning naming [what], with the error and its
/// stack trace, before the fallback is returned — it is answered, not
/// hidden. Only a caller whose failure would cost more than a missing
/// answer uses this (a search that must not fail on one bad branch); the
/// rest let the error propagate.
Future<T> fallingBackOnDatabaseError<T>(
  ScopedLogger log,
  String what,
  Future<T> Function() operation, {
  required T fallback,
}) async {
  try {
    return await toleratingClosedDatabase(log, operation, whenClosed: fallback);
  } on DatabaseException catch (error, stackTrace) {
    log.warn('$what failed', error: error, stackTrace: stackTrace);
    return fallback;
  }
}
