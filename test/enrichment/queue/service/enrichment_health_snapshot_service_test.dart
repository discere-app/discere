import 'package:discere/enrichment/pipeline/model/enrichment_work_state_count.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/enrichment_health_snapshot_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentWorkRepository workRepository;
  late EnrichmentJobRepository jobRepository;
  late EnrichmentHealthSnapshotService service;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    workRepository = EnrichmentWorkRepository(database);
    jobRepository = EnrichmentJobRepository(database);
    service = EnrichmentHealthSnapshotService(
      workRepository: workRepository,
      jobRepository: jobRepository,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('loadSnapshot combines work-state counts and cover jobs', () async {
    await workRepository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-1': {'sp-a'},
      },
      prioritizedDeckIds: ['deck-1'],
    );
    await jobRepository.scheduleDeckJob(
      deckId: 'deck-1',
      coverImageUrl: 'https://example.com/cover.jpg',
    );

    final snapshot = await service.loadSnapshot();

    expect(
      snapshot.workStateCounts.any(
        (entry) => entry.label == 'base' && entry.state == 'pending',
      ),
      isTrue,
    );
    expect(snapshot.coverJobs, hasLength(1));
    expect(snapshot.coverJobs.single.deckId, 'deck-1');
  });

  test('recoverStuckWork recovers expired cover job leases', () async {
    await jobRepository.scheduleDeckJob(
      deckId: 'deck-1',
      coverImageUrl: 'https://example.com/cover.jpg',
    );
    await database.update(
      'enrichment_jobs',
      {
        'lease_owner': 'stale-owner',
        'lease_expires_at': DateTime.now()
            .subtract(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      },
      where: 'deck_id = ?',
      whereArgs: ['deck-1'],
    );

    final recovered = await service.recoverStuckWork();

    expect(recovered, 1);
    final job = await jobRepository.loadJob('deck-1');
    expect(job!.leaseOwner, isNull);
  });

  test(
    'outstandingWorkCount sums non-terminal states and ignores terminal ones',
    () {
      const snapshot = EnrichmentHealthSnapshot(
        workStateCounts: [
          EnrichmentWorkStateCount(label: 'base', state: 'pending', count: 3),
          EnrichmentWorkStateCount(label: 'base', state: 'running', count: 1),
          EnrichmentWorkStateCount(
            label: 'base',
            state: 'retryScheduled',
            count: 2,
          ),
          EnrichmentWorkStateCount(label: 'base', state: 'done', count: 10),
          EnrichmentWorkStateCount(label: 'names', state: 'noResult', count: 4),
          EnrichmentWorkStateCount(
            label: 'names',
            state: 'permanentFailure',
            count: 5,
          ),
        ],
        coverJobs: [],
      );

      expect(snapshot.outstandingWorkCount, 6);
    },
  );
}
