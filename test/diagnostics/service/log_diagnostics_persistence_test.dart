import 'dart:io';

import 'package:discere/diagnostics/service/diagnostics_log_file.dart';
import 'package:discere/diagnostics/service/log_diagnostics_persistence.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DiagnosticsLogFile logFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'log_diagnostics_persistence_test',
    );
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'getApplicationSupportDirectory') {
            return tempDir.path;
          }
          return null;
        });

    SharedPreferences.setMockInitialValues({});
    logFile = DiagnosticsLogFile();
    Logger.configurePersistence(enabled: false);
  });

  tearDown(() async {
    Logger.configurePersistence(enabled: false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await tempDir.delete(recursive: true);
  });

  test('persists warning/error logs on a fresh install', () async {
    final prefs = await SharedPreferences.getInstance();
    final persistence = LogDiagnosticsPersistence(prefs, logFile: logFile);
    await persistence.initialize();

    Logger.warn('TestScope', 'warn message');
    Logger.error('TestScope', 'error message');
    Logger.info('TestScope', 'info message');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final content = await logFile.readAll();
    final lines = content.trim().split('\n');
    expect(lines, hasLength(2));
    expect(lines[0], contains('warning'));
    expect(lines[0], contains('TestScope'));
    expect(lines[1], contains('error'));
  });

  test('persists the error and its stack trace with the entry', () async {
    final prefs = await SharedPreferences.getInstance();
    final persistence = LogDiagnosticsPersistence(prefs, logFile: logFile);
    await persistence.initialize();

    Logger.error(
      'TestScope',
      'error message',
      error: StateError('boom'),
      stackTrace: StackTrace.fromString(
        '#0      f (package:discere/f.dart:1:1)',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final lines = (await logFile.readAll()).trim().split('\n');
    expect(
      lines.first,
      endsWith(
        ' error [TestScope] error message — StateError: Bad state: boom',
      ),
    );
    expect(lines.last, '    #0      f (package:discere/f.dart:1:1)');
  });

  test('does not persist logs when switched off', () async {
    SharedPreferences.setMockInitialValues({
      LogDiagnosticsPersistence.preferenceKey: false,
    });
    final prefs = await SharedPreferences.getInstance();
    final persistence = LogDiagnosticsPersistence(prefs, logFile: logFile);
    await persistence.initialize();

    Logger.error('TestScope', 'error message');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final content = await logFile.readAll();
    expect(content, isEmpty);
  });

  test('turns persistence on for an install that stored the old default of '
      'off, and drops the old key', () async {
    SharedPreferences.setMockInitialValues({
      'diagnostics.persist_error_logs': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final persistence = LogDiagnosticsPersistence(prefs, logFile: logFile);
    await persistence.initialize();

    Logger.error('TestScope', 'error message');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(persistence.isEnabled, isTrue);
    expect(prefs.containsKey('diagnostics.persist_error_logs'), isFalse);
    expect(await logFile.readAll(), contains('error message'));
  });
}
