import 'package:flutter_test/flutter_test.dart';

/// Pumps until [condition] holds, letting real time pass between pumps for
/// the work the test clock does not drive — isolates, files, databases. Run
/// inside `tester.runAsync`.
///
/// Waits for the condition rather than for a fixed time, so it is as fast as
/// the work under test and does not depend on how busy the machine is.
/// [timeout] only turns a hang into a failing test, and is generous for that
/// reason (see `waitForCondition`); [reason] says what was being waited for.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String? reason,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final elapsed = Stopwatch()..start();
  while (true) {
    await tester.pump();
    if (condition()) return;
    if (elapsed.elapsed > timeout) {
      fail(
        'Timed out after ${timeout.inMilliseconds} ms waiting for '
        '${reason ?? 'the condition'}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
