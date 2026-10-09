import 'dart:ui';

import 'package:discere/app/bootstrap/uncaught_error_logging.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<({LogLevel level, String scope, String message})> persisted;
  late FlutterExceptionHandler? originalFrameworkHandler;
  late ErrorCallback? originalRootZoneHandler;

  setUp(() {
    persisted = [];
    Logger.configurePersistence(
      enabled: true,
      sink: (level, scope, message) async {
        persisted.add((level: level, scope: scope, message: message));
      },
    );
    originalFrameworkHandler = FlutterError.onError;
    originalRootZoneHandler = PlatformDispatcher.instance.onError;
  });

  tearDown(() {
    // Both handlers are process-wide; the next test expects them as found.
    FlutterError.onError = originalFrameworkHandler;
    PlatformDispatcher.instance.onError = originalRootZoneHandler;
    Logger.configurePersistence(enabled: false);
  });

  test('a framework error is logged and handed on to the previous '
      'handler', () {
    final handedOn = <FlutterErrorDetails>[];
    FlutterError.onError = handedOn.add;
    installUncaughtErrorLogging();

    final details = FlutterErrorDetails(
      exception: StateError('build failed'),
      stack: StackTrace.fromString(
        '#0      build (package:discere/a.dart:1:1)',
      ),
      library: 'widgets library',
    );
    FlutterError.reportError(details);

    expect(persisted, hasLength(1));
    expect(persisted.single.level, LogLevel.error);
    expect(persisted.single.scope, 'UncaughtError');
    expect(
      persisted.single.message,
      'Framework error (widgets library) — StateError: Bad state: build '
      'failed\n    #0      build (package:discere/a.dart:1:1)',
    );
    expect(handedOn, [same(details)]);
  });

  test('an error escaping to the root zone is logged, and the previous '
      "handler's answer is kept", () {
    final handedOn = <Object>[];
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      handedOn.add(error);
      return true;
    };
    installUncaughtErrorLogging();

    final error = StateError('unawaited');
    final handled = PlatformDispatcher.instance.onError!(
      error,
      StackTrace.fromString('#0      run (package:discere/b.dart:1:1)'),
    );

    expect(persisted.single.level, LogLevel.error);
    expect(persisted.single.scope, 'UncaughtError');
    expect(
      persisted.single.message,
      startsWith(
        'Unhandled asynchronous error — StateError: Bad state: '
        'unawaited\n    #0      run',
      ),
    );
    expect(handedOn, [same(error)]);
    expect(handled, isTrue);
  });

  test('without a previous root-zone handler the error is left to the '
      'engine', () {
    PlatformDispatcher.instance.onError = null;
    installUncaughtErrorLogging();

    final handled = PlatformDispatcher.instance.onError!(
      StateError('unawaited'),
      StackTrace.empty,
    );

    expect(handled, isFalse);
    expect(persisted, hasLength(1));
  });

  test('installing twice logs each error once', () {
    PlatformDispatcher.instance.onError = null;
    installUncaughtErrorLogging();
    installUncaughtErrorLogging();

    PlatformDispatcher.instance.onError!(StateError('once'), StackTrace.empty);

    expect(persisted, hasLength(1));
  });
}
