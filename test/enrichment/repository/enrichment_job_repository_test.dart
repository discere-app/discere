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

  test(
    'markStageRetryScheduled sets next_attempt_at from the retry count',
    () async {
      await repository.scheduleDeckJob(
        deckId: 'deck-retry',
        speciesIds: {'sp1'},
        includeINatPhotos: true,
        includeCommonNames: true,
      );

      final claimed = await repository.claimNextJob(
        owner: 'owner-1',
        leaseDuration: const Duration(minutes: 5),
        runnerKind: EnrichmentRunnerKind.foreground,
      );
      final stage = repository.nextRunnableStage(claimed!);
      expect(stage, isNotNull);

      final before = DateTime.now();
      await repository.markStageRetryScheduled(
        deckId: 'deck-retry',
        stage: stage!,
        owner: 'owner-1',
        error: 'boom',
        failureKind: 'temporary',
      );

      final job = await repository.loadJob('deck-retry');
      expect(job!.status, EnrichmentJobStatus.retryScheduled);
      expect(job.retryCount, 1);
      expect(job.leaseOwner, isNull);
      expect(job.nextAttemptAt, isNotNull);
      expect(job.nextAttemptAt!.difference(before).inSeconds, closeTo(15, 2));
    },
  );

  test(
    'markStageRetryScheduled backoff escalates with each retry and caps out',
    () async {
      await repository.scheduleDeckJob(
        deckId: 'deck-retry',
        speciesIds: {'sp1'},
        includeINatPhotos: true,
        includeCommonNames: true,
      );

      Future<Duration> retryOnceAndGetDelay() async {
        final claimed = await repository.claimNextJob(
          owner: 'owner-1',
          leaseDuration: const Duration(minutes: 5),
          runnerKind: EnrichmentRunnerKind.foreground,
        );
        final stage = repository.nextRunnableStage(claimed!);
        final before = DateTime.now();
        await repository.markStageRetryScheduled(
          deckId: 'deck-retry',
          stage: stage!,
          owner: 'owner-1',
          error: 'boom',
          failureKind: 'temporary',
        );
        final job = await repository.loadJob('deck-retry');
        return job!.nextAttemptAt!.difference(before);
      }

      final delaysInSeconds = [
        for (var i = 0; i < 6; i++) (await retryOnceAndGetDelay()).inSeconds,
      ];

      // Steps: 15s, 30s, 1m, 2m, 4m, then capped at 4m for every retry after.
      expect(delaysInSeconds[0], closeTo(15, 2));
      expect(delaysInSeconds[1], closeTo(30, 2));
      expect(delaysInSeconds[2], closeTo(60, 2));
      expect(delaysInSeconds[3], closeTo(120, 2));
      expect(delaysInSeconds[4], closeTo(240, 2));
      expect(delaysInSeconds[5], closeTo(240, 2));
    },
  );
}
