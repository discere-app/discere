import 'package:discere/shared/persistence/closed_database_tolerance.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const log = ScopedLogger('ClosedDatabaseToleranceTest');
  late Database db;
  late List<({LogLevel level, String message})> persisted;

  setUp(() async {
    db = await openInMemoryUserDatabase();
    persisted = [];
    Logger.configurePersistence(
      enabled: true,
      sink: (level, scope, message) async {
        persisted.add((level: level, message: message));
      },
    );
  });

  tearDown(() async {
    Logger.configurePersistence(enabled: false);
    if (db.isOpen) await db.close();
  });

  Future<List<Map<String, Object?>>> queryMissingTable() =>
      db.rawQuery('SELECT * FROM no_such_table');

  Future<List<Map<String, Object?>>> queryClosedDatabase() async {
    await db.close();
    return db.rawQuery('SELECT 1');
  }

  group('toleratingClosedDatabase', () {
    test('passes the result through', () async {
      final rows = await toleratingClosedDatabase(
        log,
        () => db.rawQuery('SELECT 7 AS answer'),
        whenClosed: const [],
      );

      expect(rows.single['answer'], 7);
    });

    test('answers whenClosed when the database is closed underneath the '
        'call', () async {
      final rows = await toleratingClosedDatabase(
        log,
        queryClosedDatabase,
        whenClosed: const [
          <String, Object?>{'fallback': true},
        ],
      );

      expect(rows.single['fallback'], isTrue);
      expect(persisted, isEmpty);
    });

    test('rethrows any other database error with its original stack '
        'trace', () async {
      StackTrace? thrownWith;
      Future<List<Map<String, Object?>>> operation() async {
        try {
          return await queryMissingTable();
        } catch (_, stackTrace) {
          thrownWith = stackTrace;
          rethrow;
        }
      }

      Object? caught;
      StackTrace? caughtWith;
      try {
        await toleratingClosedDatabase(log, operation, whenClosed: const []);
      } catch (error, stackTrace) {
        caught = error;
        caughtWith = stackTrace;
      }

      expect(
        caught,
        isA<DatabaseException>().having(
          (e) => e.isNoSuchTableError('no_such_table'),
          'isNoSuchTableError',
          isTrue,
        ),
      );
      expect(caughtWith, same(thrownWith));
      expect(persisted, isEmpty);
    });
  });

  group('runToleratingClosedDatabase', () {
    test('answers true once the operation completed', () async {
      final ran = await runToleratingClosedDatabase(
        log,
        () => db.rawQuery('SELECT 1'),
      );

      expect(ran, isTrue);
    });

    test('answers false when the database is closed underneath the '
        'call', () async {
      expect(
        await runToleratingClosedDatabase(log, queryClosedDatabase),
        isFalse,
      );
    });

    test('rethrows any other database error', () async {
      await expectLater(
        runToleratingClosedDatabase(log, queryMissingTable),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('fallingBackOnDatabaseError', () {
    test('passes the result through', () async {
      final rows = await fallingBackOnDatabaseError(
        log,
        'Lookup',
        () => db.rawQuery('SELECT 7 AS answer'),
        fallback: const [],
      );

      expect(rows.single['answer'], 7);
      expect(persisted, isEmpty);
    });

    test('falls back silently when the database is closed', () async {
      final rows = await fallingBackOnDatabaseError(
        log,
        'Lookup',
        queryClosedDatabase,
        fallback: const [],
      );

      expect(rows, isEmpty);
      expect(persisted, isEmpty);
    });

    test('falls back on any other database error and logs it as a warning '
        'with error and stack trace', () async {
      final rows = await fallingBackOnDatabaseError(
        log,
        'Lookup',
        queryMissingTable,
        fallback: const [],
      );

      expect(rows, isEmpty);
      expect(persisted.single.level, LogLevel.warning);
      final lines = persisted.single.message.split('\n');
      expect(lines.first, startsWith('Lookup failed — '));
      expect(lines.first, contains('no such table: no_such_table'));
      expect(lines.length, greaterThan(1));
    });
  });
}
