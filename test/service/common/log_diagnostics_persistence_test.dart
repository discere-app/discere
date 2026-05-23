import 'dart:io';

import 'package:discere/shared/repository/local_diagnostics_repository.dart';
import 'package:discere/shared/service/local_diagnostics.dart';
import 'package:discere/shared/service/log_diagnostics_persistence.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late LocalDiagnosticsRepository repository;
  late LocalDiagnostics diagnostics;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = await openDatabase(inMemoryDatabasePath, version: 1);
    await database.execute(
      await File(
        'assets/sql/user_db/tables/create_local_diagnostics_events.sql',
      ).readAsString(),
    );
    await database.execute(
      await File(
        'assets/sql/user_db/tables/create_local_diagnostics_network_failures.sql',
      ).readAsString(),
    );
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
