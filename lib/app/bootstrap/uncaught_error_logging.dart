import 'dart:ui';

import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';

/// The scope every unhandled error is logged under — the string to search
/// an exported diagnostics log for.
const _scope = 'UncaughtError';

/// Logs every error nothing else handled through [Logger.error], with its
/// stack trace, so it reaches the persisted diagnostics log in release
/// builds too.
///
/// Covers both ways an error goes unhandled: one the framework catches
/// (build, layout, gesture callbacks — [FlutterError.onError]) and one that
/// escapes to the root zone, such as a failed future nobody awaits
/// ([PlatformDispatcher.onError]). Whatever handler was installed before
/// still runs afterwards, so the default console report stays as it is.
///
/// Installing twice keeps a single link in each chain. `main()` runs once
/// per isolate in the app, but integration tests call it once per test.
void installUncaughtErrorLogging() {
  if (FlutterError.onError != _logFrameworkError) {
    _nextFrameworkErrorHandler = FlutterError.onError;
    FlutterError.onError = _logFrameworkError;
  }
  final dispatcher = PlatformDispatcher.instance;
  if (dispatcher.onError != _logRootZoneError) {
    _nextRootZoneErrorHandler = dispatcher.onError;
    dispatcher.onError = _logRootZoneError;
  }
}

FlutterExceptionHandler? _nextFrameworkErrorHandler;
ErrorCallback? _nextRootZoneErrorHandler;

void _logFrameworkError(FlutterErrorDetails details) {
  Logger.error(
    _scope,
    'Framework error (${details.library ?? 'unknown library'})',
    error: details.exception,
    stackTrace: details.stack,
  );
  _nextFrameworkErrorHandler?.call(details);
}

/// Returns what the next handler returns — false without one, which leaves
/// the engine's own report in place.
bool _logRootZoneError(Object error, StackTrace stackTrace) {
  Logger.error(
    _scope,
    'Unhandled asynchronous error',
    error: error,
    stackTrace: stackTrace,
  );
  return _nextRootZoneErrorHandler?.call(error, stackTrace) ?? false;
}
