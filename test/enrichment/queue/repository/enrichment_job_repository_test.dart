import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentJobRepository repository;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    repository = EnrichmentJobRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'scheduleDeckJob with a cover URL leaves the cover stage pending',
    () async {
      await repository.scheduleDeckJob(
        deckId: 'deck-1',
        coverImageUrl: 'https://example.com/cover.jpg',
      );

      final job = await repository.loadJob('deck-1');
      expect(job, isNotNull);
      expect(job!.payload.coverImageUrl, 'https://example.com/cover.jpg');
      expect(
        job.stageStates[EnrichmentStage.cover],
        EnrichmentStageState.pending,
      );
      expect(repository.nextRunnableStage(job), EnrichmentStage.cover);
    },
  );

  test(
    'scheduleDeckJob without a cover URL is born completed with a skipped '
    'cover stage',
    () async {
      await repository.scheduleDeckJob(deckId: 'deck-1');

      final job = await repository.loadJob('deck-1');
      expect(job, isNotNull);
      expect(job!.payload.coverImageUrl, isNull);
      expect(
        job.stageStates[EnrichmentStage.cover],
        EnrichmentStageState.skipped,
      );
      // Nothing to download, so the job is terminal up front — otherwise it
      // would sit at `queued` forever (claimNextJob only claims a `pending`
      // cover stage), leaving coverTerminal false and blocking the deck from
      // ever reaching done. completed_at stays null: nothing was downloaded,
      // so the cover has no meaningful completion moment.
      expect(job.status, EnrichmentJobStatus.completed);
      expect(job.completedAt, isNull);
      expect(repository.nextRunnableStage(job), isNull);
      expect(job.hasPendingWork, isFalse);
    },
  );

  test('claimNextJob picks up retryScheduled jobs immediately', () async {
    await repository.scheduleDeckJob(
      deckId: 'deck-1',
      coverImageUrl: 'https://example.com/cover.jpg',
    );

    await database.update(
      EnrichmentJobRepository.jobsTable,
      {'status': EnrichmentJobStatus.retryScheduled.name, 'retry_count': 1},
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
    'clearRetryAttemptForRetryScheduledJobs resets future next_attempt_at',
    () async {
      await repository.scheduleDeckJob(
        deckId: 'deck-stale',
        coverImageUrl: 'https://example.com/cover.jpg',
      );
      await repository.scheduleDeckJob(
        deckId: 'deck-running',
        coverImageUrl: 'https://example.com/cover.jpg',
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

      final cleared = await repository.clearRetryAttemptForRetryScheduledJobs();
      expect(cleared, 1);

      final stale = await repository.loadJob('deck-stale');
      final running = await repository.loadJob('deck-running');
      expect(stale!.nextAttemptAt, isNull);
      expect(running!.nextAttemptAt, isNotNull);
    },
  );

  test(
    'cancelAllNonTerminalJobs cancels every non-terminal job and skips its '
    'cover stage, leaving already-terminal jobs untouched',
    () async {
      await repository.scheduleDeckJob(
        deckId: 'deck-running',
        coverImageUrl: 'https://example.com/cover.jpg',
      );
      await database.update(
        EnrichmentJobRepository.jobsTable,
        {
          'status': EnrichmentJobStatus.runningForeground.name,
          'lease_owner': 'stale-owner',
          'lease_expires_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'deck_id = ?',
        whereArgs: ['deck-running'],
      );
      await database.update(
        EnrichmentJobRepository.stagesTable,
        {'state': EnrichmentStageState.running.name},
        where: 'deck_id = ?',
        whereArgs: ['deck-running'],
      );

      await repository.scheduleDeckJob(
        deckId: 'deck-no-cover',
      ); // born completed with a skipped cover stage.

      final cancelledCount = await repository.cancelAllNonTerminalJobs();
      expect(cancelledCount, 1);

      final running = await repository.loadJob('deck-running');
      expect(running!.status, EnrichmentJobStatus.cancelled);
      expect(running.leaseOwner, isNull);
      expect(running.currentStage, isNull);
      expect(
        running.stageStates[EnrichmentStage.cover],
        EnrichmentStageState.skipped,
      );

      // Already-terminal (completed) job is untouched.
      final noCover = await repository.loadJob('deck-no-cover');
      expect(noCover!.status, EnrichmentJobStatus.completed);
    },
  );

  test(
    'markStageRetryScheduled sets next_attempt_at from the retry count',
    () async {
      await repository.scheduleDeckJob(
        deckId: 'deck-retry',
        coverImageUrl: 'https://example.com/cover.jpg',
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
        coverImageUrl: 'https://example.com/cover.jpg',
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

  test(
    'markStageSucceeded completes the job — cover is the only stage left',
    () async {
      await repository.scheduleDeckJob(
        deckId: 'deck-1',
        coverImageUrl: 'https://example.com/cover.jpg',
      );
      final claimed = await repository.claimNextJob(
        owner: 'owner-1',
        leaseDuration: const Duration(minutes: 5),
        runnerKind: EnrichmentRunnerKind.foreground,
      );
      final stage = repository.nextRunnableStage(claimed!)!;
      await repository.markStageRunning(
        deckId: 'deck-1',
        stage: stage,
        owner: 'owner-1',
        runnerKind: EnrichmentRunnerKind.foreground,
      );

      await repository.markStageSucceeded(
        deckId: 'deck-1',
        stage: stage,
        owner: 'owner-1',
      );

      final job = await repository.loadJob('deck-1');
      expect(job!.status, EnrichmentJobStatus.completed);
      expect(job.completedAt, isNotNull);
      expect(job.hasPendingWork, isFalse);
    },
  );

  test('deleteDeckJob removes the job and its stage rows', () async {
    await repository.scheduleDeckJob(
      deckId: 'deck-1',
      coverImageUrl: 'https://example.com/cover.jpg',
    );
    await repository.markStageRunning(
      deckId: 'deck-1',
      stage: EnrichmentStage.cover,
      owner: 'owner-1',
      runnerKind: EnrichmentRunnerKind.foreground,
    );

    await repository.deleteDeckJob('deck-1');

    expect(await repository.loadJob('deck-1'), isNull);
    final stageRows = await database.query(
      EnrichmentJobRepository.stagesTable,
      where: 'deck_id = ?',
      whereArgs: ['deck-1'],
    );
    expect(stageRows, isEmpty);
  });

  test('pruneJobsNotIn deletes jobs for decks no longer present', () async {
    await repository.scheduleDeckJob(
      deckId: 'deck-keep',
      coverImageUrl: 'https://example.com/cover.jpg',
    );
    await repository.scheduleDeckJob(
      deckId: 'deck-orphan',
      coverImageUrl: 'https://example.com/cover.jpg',
    );

    await repository.pruneJobsNotIn({'deck-keep'});

    expect(await repository.loadJob('deck-keep'), isNotNull);
    expect(await repository.loadJob('deck-orphan'), isNull);
  });

  test('pruneJobsNotIn is a no-op when given an empty set', () async {
    await repository.scheduleDeckJob(
      deckId: 'deck-1',
      coverImageUrl: 'https://example.com/cover.jpg',
    );

    await repository.pruneJobsNotIn(const {});

    expect(await repository.loadJob('deck-1'), isNotNull);
  });

  test(
    'loadJobsUpdatedSince excludes jobs updated strictly before the cursor',
    () async {
      await repository.scheduleDeckJob(
        deckId: 'deck-1',
        coverImageUrl: 'https://example.com/cover.jpg',
      );
      final job = await repository.loadJob('deck-1');
      final past = job!.updatedAt.subtract(const Duration(seconds: 5));
      await database.update(
        EnrichmentJobRepository.jobsTable,
        {'updated_at': past.millisecondsSinceEpoch},
        where: 'deck_id = ?',
        whereArgs: ['deck-1'],
      );

      final changed = await repository.loadJobsUpdatedSince(
        past.add(const Duration(seconds: 1)),
      );

      expect(changed, isEmpty);
    },
  );

  test('loadJobsUpdatedSince includes rows sharing the cursor\'s exact '
      'millisecond, not just strictly newer ones', () async {
    await repository.scheduleDeckJob(
      deckId: 'deck-old',
      coverImageUrl: 'https://example.com/cover.jpg',
    );
    final cursor = (await repository.loadJob('deck-old'))!.updatedAt;

    // Two siblings stamped with the exact same millisecond as the cursor —
    // a real scenario when two decks progress in the same batch. `>=`
    // must return both instead of silently dropping whichever one a
    // strict `>` comparison would exclude.
    await repository.scheduleDeckJob(
      deckId: 'deck-a',
      coverImageUrl: 'https://example.com/cover.jpg',
    );
    await repository.scheduleDeckJob(
      deckId: 'deck-b',
      coverImageUrl: 'https://example.com/cover.jpg',
    );
    await database.update(
      EnrichmentJobRepository.jobsTable,
      {'updated_at': cursor.millisecondsSinceEpoch},
      where: 'deck_id IN (?, ?)',
      whereArgs: ['deck-a', 'deck-b'],
    );

    final changed = await repository.loadJobsUpdatedSince(cursor);
    final deckIds = changed.map((job) => job.deckId).toSet();

    expect(deckIds, containsAll(['deck-a', 'deck-b']));
  });
}
