import 'dart:math';

import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FixedRandom implements Random {
  final int Function(int max) _nextInt;

  _FixedRandom(this._nextInt);

  @override
  bool nextBool() => _nextInt(2) == 1;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => _nextInt(max);
}

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

  test(
    'computeRetryDelay uses 12h to 24h jitter after a failed retry at the 30 minute cap',
    () {
      expect(
        EnrichmentJobRepository.computeRetryDelay(
          retryCount: 1,
          random: _FixedRandom((_) => 0),
        ),
        Duration.zero,
      );
      expect(
        EnrichmentJobRepository.computeRetryDelay(
          retryCount: 2,
          random: _FixedRandom((max) => max - 1),
        ),
        const Duration(seconds: 60),
      );
      expect(
        EnrichmentJobRepository.computeRetryDelay(
          retryCount: 7,
          random: _FixedRandom((max) => max - 1),
        ),
        const Duration(minutes: 30),
      );
      expect(
        EnrichmentJobRepository.computeRetryDelay(
          retryCount: 8,
          random: _FixedRandom((_) => 0),
        ),
        const Duration(hours: 12),
      );
      expect(
        EnrichmentJobRepository.computeRetryDelay(
          retryCount: 8,
          random: _FixedRandom((max) => max - 1),
        ),
        const Duration(hours: 24),
      );
    },
  );

  test('claimNextJob skips jobs with an active retry backoff', () async {
    await repository.scheduleDeckJob(
      deckId: 'deck-1',
      speciesIds: {'sp1'},
      includeINatPhotos: true,
      includeCommonNames: true,
    );
    await repository.scheduleDeckJob(
      deckId: 'deck-2',
      speciesIds: {'sp2'},
      includeINatPhotos: true,
      includeCommonNames: true,
    );

    await database.update(
      EnrichmentJobRepository.jobsTable,
      {
        'status': EnrichmentJobStatus.retryScheduled.name,
        'retry_count': 1,
        'next_attempt_at': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
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
    expect(claimed!.deckId, 'deck-2');
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
}
