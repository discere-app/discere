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

  test('persists warning/error logs when enabled in preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final persistence = LogDiagnosticsPersistence(prefs, logFile: logFile);
    await persistence.initialize(defaultEnabled: true);

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

  test('does not persist logs when disabled in preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final persistence = LogDiagnosticsPersistence(prefs, logFile: logFile);
    await persistence.initialize(defaultEnabled: false);

    Logger.error('TestScope', 'error message');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final content = await logFile.readAll();
    expect(content, isEmpty);
  });
}
