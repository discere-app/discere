import 'package:discere/diagnostics/repository/local_diagnostics_repository.dart';
import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/diagnostics/service/log_diagnostics_persistence.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/in_memory_user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late LocalDiagnosticsRepository repository;
  late LocalDiagnostics diagnostics;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = await openInMemoryUserDatabase();
    repository = LocalDiagnosticsRepository(database);
    diagnostics = LocalDiagnostics(repository: repository, enabled: true);
    Logger.configurePersistence(enabled: false);
  });

  tearDown(() async {
    Logger.configurePersistence(enabled: false);
    await database.close();
  });

  test('persists warning/error logs when enabled in preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final persistence = LogDiagnosticsPersistence(
      prefs,
      diagnostics: diagnostics,
    );
    await persistence.initialize(defaultEnabled: true);

    Logger.warn('TestScope', 'warn message');
    Logger.error('TestScope', 'error message');
    Logger.info('TestScope', 'info message');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final rows = await repository.loadRecentEvents(limit: 10);
    expect(rows, hasLength(2));
    expect(rows.first['category'], 'log');
    expect(rows.first['subject_id'], 'TestScope');
  });

  test('does not persist logs when disabled in preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final persistence = LogDiagnosticsPersistence(
      prefs,
      diagnostics: diagnostics,
    );
    await persistence.initialize(defaultEnabled: false);

    Logger.error('TestScope', 'error message');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final rows = await repository.loadRecentEvents(limit: 10);
    expect(rows, isEmpty);
  });
}
