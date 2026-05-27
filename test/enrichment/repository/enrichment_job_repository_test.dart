import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentJobRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await openDatabase(inMemoryDatabasePath, version: 1);
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_jobs.sql',
      ),
    );
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_job_stages.sql',
      ),
    );
    repository = EnrichmentJobRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('claimNextJob picks up retryScheduled jobs immediately', () async {
    await repository.scheduleDeckJob(
      deckId: 'deck-1',
      speciesIds: {'sp1'},
      includeINatPhotos: true,
      includeCommonNames: true,
    );

    await database.update(
      EnrichmentJobRepository.jobsTable,
      {
        'status': EnrichmentJobStatus.retryScheduled.name,
        'retry_count': 1,
      },
      where: 'deck_id = ?',
      whereArgs: ['deck-1'],
    );

    final claimed = await repository.claimNextJob(
      owner: 'foreground-owner',
      leaseDuration: const Duration(minutes: 5),
      runnerKind: EnrichmentRunnerKind.foreground,
    );

    expect(claimed, isNotNull);
    expect(claimed!.deckId, 'deck-1');
  });

  test(
    'scheduleDeckJob preserves species order while removing duplicates',
    () async {
      await repository.scheduleDeckJob(
        deckId: 'deck-1',
        speciesIds: ['sp3', 'sp1', 'sp3', 'sp2', ' sp1 '],
        includeINatPhotos: true,
        includeCommonNames: true,
      );

      final job = await repository.loadJob('deck-1');

      expect(job, isNotNull);
      expect(job!.payload.speciesIds, ['sp3', 'sp1', 'sp2']);
    },
  );

  test(
    'clearRetryAttemptForRetryScheduledJobs resets future next_attempt_at',
    () async {
      await repository.scheduleDeckJob(
        deckId: 'deck-stale',
        speciesIds: {'sp1'},
        includeINatPhotos: true,
        includeCommonNames: true,
      );
      await repository.scheduleDeckJob(
        deckId: 'deck-running',
        speciesIds: {'sp2'},
        includeINatPhotos: true,
        includeCommonNames: true,
      );

      final futureMillis = DateTime.now()
          .add(const Duration(hours: 12))
          .millisecondsSinceEpoch;
      await database.update(
        EnrichmentJobRepository.jobsTable,
        {
          'status': EnrichmentJobStatus.retryScheduled.name,
          'next_attempt_at': futureMillis,
        },
        where: 'deck_id = ?',
        whereArgs: ['deck-stale'],
      );
      // Running jobs must not be touched.
      await database.update(
        EnrichmentJobRepository.jobsTable,
        {
          'status': EnrichmentJobStatus.runningForeground.name,
          'next_attempt_at': futureMillis,
        },
        where: 'deck_id = ?',
        whereArgs: ['deck-running'],
      );

      final cleared = await repository
          .clearRetryAttemptForRetryScheduledJobs();
      expect(cleared, 1);

      final stale = await repository.loadJob('deck-stale');
      final running = await repository.loadJob('deck-running');
      expect(stale!.nextAttemptAt, isNull);
      expect(running!.nextAttemptAt, isNotNull);
    },
  );
}
