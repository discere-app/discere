import 'dart:io';

import 'package:discere/diagnostics/service/diagnostics_log_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DiagnosticsLogFile logFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diagnostics_log_file_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'getApplicationSupportDirectory') {
            return tempDir.path;
          }
          return null;
        });
    logFile = DiagnosticsLogFile();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await tempDir.delete(recursive: true);
  });

  test('readAll returns empty string when no file exists yet', () async {
    expect(await logFile.readAll(), isEmpty);
  });

  test('appendLine writes lines in order', () async {
    await logFile.appendLine('first');
    await logFile.appendLine('second');

    final content = await logFile.readAll();
    expect(content.trim().split('\n'), ['first', 'second']);
  });

  test('clear empties the file', () async {
    await logFile.appendLine('first');
    await logFile.clear();

    expect(await logFile.readAll(), isEmpty);
  });

  test('trims the file once it exceeds the size cap', () async {
    // Each line is ~50 bytes; write well past the 1MB cap so a trim fires.
    final longLine = 'x' * 50;
    for (var i = 0; i < 25000; i++) {
      await logFile.appendLine('$i-$longLine');
    }

    final file = await logFile.file();
    final size = await file.length();
    expect(size, lessThan(1024 * 1024));

    final content = await logFile.readAll();
    // Oldest lines should have been dropped, newest line preserved. The
    // dropped-line check is anchored on a leading newline so it can't
    // false-match a surviving line like "110-..." containing "0-..." as a
    // plain substring.
    expect(content, contains('24999-$longLine'));
    expect(content, isNot(contains('\n0-$longLine\n')));
  });
}
