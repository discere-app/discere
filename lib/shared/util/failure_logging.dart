import 'package:discere/shared/util/logger.dart';

/// Logging for a failure that the UI shows instead of awaiting.
///
/// A `FutureBuilder` that renders an error has consumed it: the error never
/// reaches the uncaught-error log, so unless it is logged where the future
/// is made, it reaches the diagnostics not at all. Logging it from `build`
/// instead would add an entry on every rebuild rather than one per failure.
extension FailureLogging<T> on Future<T> {
  /// This future, with a failure logged once as the warning `<what> failed`,
  /// error and stack trace attached, and then passed on unchanged — whatever
  /// shows it still gets the same error with the same stack trace.
  Future<T> warnOnFailure(ScopedLogger log, String what) {
    return onError<Object>((error, stackTrace) {
      log.warn('$what failed', error: error, stackTrace: stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    });
  }
}
