import 'dart:async';

import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/service/enrichment_job_executor.dart';
import 'package:discere/enrichment/service/enrichment_job_ports.dart';
import 'package:discere/shared/service/local_diagnostics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../service/mocks.mocks.dart';

/// Records every cover-path update so tests can assert on it without a real
/// deck repository.
class _FakeDeckCoverStore implements DeckCoverStorePort {
  final List<(String, String)> updates = [];

  @override
  Future<void> updateDeckCoverPath(String deckId, String localPath) async {
    updates.add((deckId, localPath));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentJobRepository jobRepository;
  late MockEnrichmentService enrichmentService;
  late MockImageService imageService;
  late _FakeDeckCoverStore coverStore;
  late EnrichmentJobExecutor executor;

  setUpAll(() {
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
    jobRepository = EnrichmentJobRepository(database);
    enrichmentService = MockEnrichmentService();
    imageService = MockImageService();
    coverStore = _FakeDeckCoverStore();
    executor = EnrichmentJobExecutor(
      enrichmentService,
      jobRepository,
      deckCoverStore: coverStore,
      imageService: imageService,
      workRepository: const EnrichmentWorkRepository(),
      diagnostics: LocalDiagnostics(enabled: false),
    );
  });

  tearDown(() async {
    await database.close();
  });

  // Scheduling a job with a cover URL but no iNat photos/common names makes
  // `cover` the only stage this test drives; every other stage stays
  // `skipped`, so `processUntilIdle(maxStageRuns: 1)` deterministically
  // targets `cover` without needing to fake the whole species pipeline.
  Future<void> scheduleJobWithCoverOnly(
    String deckId, {
    String coverUrl = 'https://example.com/cover.jpg',
  }) {
    return jobRepository.scheduleDeckJob(
      deckId: deckId,
      speciesIds: {'sp1'},
      includeINatPhotos: false,
      includeCommonNames: false,
      coverImageUrl: coverUrl,
    );
  }

  test('successful cover download marks the cover stage succeeded', () async {
    await scheduleJobWithCoverOnly('deck-1');
    when(
      imageService.downloadAndSaveDeckCover(any),
    ).thenAnswer((_) async => '/local/cover.jpg');

    final processedAny = await executor.processUntilIdle(
      owner: 'owner-1',
      runnerKind: EnrichmentRunnerKind.foreground,
      maxStageRuns: 1,
    );

    expect(processedAny, isTrue);
    expect(coverStore.updates, [('deck-1', '/local/cover.jpg')]);
    final job = await jobRepository.loadJob('deck-1');
    expect(
      job!.stageStates[EnrichmentStage.cover],
      EnrichmentStageState.succeeded,
    );
    expect(job.status, isNot(EnrichmentJobStatus.retryScheduled));
    expect(job.retryCount, 0);
  });

  test(
    'a timeout schedules a retry with an escalating backoff instead of failing the job',
    () async {
      await scheduleJobWithCoverOnly('deck-1');
      when(
        imageService.downloadAndSaveDeckCover(any),
      ).thenThrow(TimeoutException('slow host'));

      final before = DateTime.now();
      await executor.processUntilIdle(
        owner: 'owner-1',
        runnerKind: EnrichmentRunnerKind.foreground,
        maxStageRuns: 1,
      );

      final job = await jobRepository.loadJob('deck-1');
      expect(job!.status, EnrichmentJobStatus.retryScheduled);
      expect(job.retryCount, 1);
      expect(
        job.stageStates[EnrichmentStage.cover],
        EnrichmentStageState.pending,
      );
      expect(job.nextAttemptAt, isNotNull);
      expect(
        job.nextAttemptAt!.difference(before).inSeconds,
        closeTo(15, 2),
      );
    },
  );

  test(
    'a non-retryable error fails the stage permanently on the first attempt',
    () async {
      await scheduleJobWithCoverOnly('deck-1');
      when(
        imageService.downloadAndSaveDeckCover(any),
      ).thenThrow(StateError('boom'));

      await executor.processUntilIdle(
        owner: 'owner-1',
        runnerKind: EnrichmentRunnerKind.foreground,
        maxStageRuns: 1,
      );

      final job = await jobRepository.loadJob('deck-1');
      expect(job!.status, EnrichmentJobStatus.failedPermanent);
      expect(job.failureKind, 'permanent');
      expect(job.retryCount, 0);
    },
  );

  test(
    'a temporary failure that keeps recurring escalates to failedPermanent after the retry cap',
    () async {
      await scheduleJobWithCoverOnly('deck-1');
      when(
        imageService.downloadAndSaveDeckCover(any),
      ).thenThrow(TimeoutException('slow host'));

      // Drive one stage-attempt per call so each retry round-trips through
      // the repository individually, rather than letting a single
      // processUntilIdle call burn through several attempts back-to-back.
      for (var attempt = 0; attempt < 5; attempt++) {
        await executor.processUntilIdle(
          owner: 'owner-1',
          runnerKind: EnrichmentRunnerKind.foreground,
          maxStageRuns: 1,
        );
      }

      final job = await jobRepository.loadJob('deck-1');
      expect(job!.status, EnrichmentJobStatus.failedPermanent);
      expect(job.failureKind, 'temporary_retries_exhausted');
      expect(
        job.stageStates[EnrichmentStage.cover],
        EnrichmentStageState.failed,
      );
    },
  );

  test(
    'a temporary failure below the retry cap keeps retrying instead of failing permanently',
    () async {
      await scheduleJobWithCoverOnly('deck-1');
      when(
        imageService.downloadAndSaveDeckCover(any),
      ).thenThrow(TimeoutException('slow host'));

      for (var attempt = 0; attempt < 4; attempt++) {
        await executor.processUntilIdle(
          owner: 'owner-1',
          runnerKind: EnrichmentRunnerKind.foreground,
          maxStageRuns: 1,
        );
      }

      final job = await jobRepository.loadJob('deck-1');
      expect(job!.status, EnrichmentJobStatus.retryScheduled);
      expect(job.retryCount, 4);
    },
  );

  test(
    'processUntilIdle stops after maxStageRuns even though more work is pending',
    () async {
      await scheduleJobWithCoverOnly('deck-1');
      await scheduleJobWithCoverOnly('deck-2');
      when(
        imageService.downloadAndSaveDeckCover(any),
      ).thenAnswer((_) async => '/local/cover.jpg');

      final processedAny = await executor.processUntilIdle(
        owner: 'owner-1',
        runnerKind: EnrichmentRunnerKind.foreground,
        maxStageRuns: 1,
      );

      expect(processedAny, isTrue);
      final job1 = await jobRepository.loadJob('deck-1');
      final job2 = await jobRepository.loadJob('deck-2');
      final succeededCount = [job1, job2]
          .where(
            (job) =>
                job!.stageStates[EnrichmentStage.cover] ==
                EnrichmentStageState.succeeded,
          )
          .length;
      // Exactly one deck's cover stage should have been processed; the
      // other is left pending for the next processUntilIdle call.
      expect(succeededCount, 1);
    },
  );

  test('processUntilIdle returns false when there is no claimable job', () async {
    final processedAny = await executor.processUntilIdle(
      owner: 'owner-1',
      runnerKind: EnrichmentRunnerKind.foreground,
    );

    expect(processedAny, isFalse);
    verifyNever(imageService.downloadAndSaveDeckCover(any));
  });

  test(
    'processUntilIdle stops early once shouldStop returns true',
    () async {
      await scheduleJobWithCoverOnly('deck-1');
      when(
        imageService.downloadAndSaveDeckCover(any),
      ).thenAnswer((_) async => '/local/cover.jpg');

      final processedAny = await executor.processUntilIdle(
        owner: 'owner-1',
        runnerKind: EnrichmentRunnerKind.foreground,
        shouldStop: () => true,
      );

      expect(processedAny, isFalse);
      verifyNever(imageService.downloadAndSaveDeckCover(any));
      final job = await jobRepository.loadJob('deck-1');
      expect(job!.status, EnrichmentJobStatus.queued);
    },
  );
}
