import 'package:discere/shared/util/failure_logging.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/persisted_warnings.dart';

void main() {
  const log = ScopedLogger('FailureLoggingTest');
  late List<String> warnings;

  setUp(() => warnings = recordPersistedWarnings());

  test('passes a value through without logging', () async {
    expect(await Future.value(7).warnOnFailure(log, 'Answer load'), 7);
    expect(warnings, isEmpty);
  });

  test('logs a failure once as a warning with its stack trace and passes the '
      'same error and stack trace on', () async {
    final failure = StateError('broken');
    final thrownWith = StackTrace.current;

    Object? caught;
    StackTrace? caughtWith;
    try {
      await Future<int>.error(
        failure,
        thrownWith,
      ).warnOnFailure(log, 'Answer load');
    } catch (error, stackTrace) {
      caught = error;
      caughtWith = stackTrace;
    }

    expect(caught, same(failure));
    expect(caughtWith, same(thrownWith));
    expect(warnings, hasLength(1));
    expect(
      warnings.single,
      startsWith(
        '[FailureLoggingTest] Answer load failed — StateError: Bad state: '
        'broken',
      ),
    );
    expect(warnings.single, contains('\n    #0 '));
  });

  test('logs once however often the failed future is listened to', () async {
    final future = Future<int>.error(
      StateError('broken'),
    ).warnOnFailure(log, 'Answer load');

    await expectLater(future, throwsStateError);
    await expectLater(future, throwsStateError);

    expect(warnings, hasLength(1));
  });
}
