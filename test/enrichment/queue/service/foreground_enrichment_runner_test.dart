import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_claim_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_outcome_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:discere/enrichment/pipeline/service/base_worker.dart';
import 'package:discere/enrichment/pipeline/service/inat_worker.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/cover_job_runner.dart';
import 'package:discere/enrichment/queue/service/foreground_enrichment_runner.dart';
import 'package:discere/enrichment/service/deck_membership_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../mocks.mocks.dart';
import '../../../support/in_memory_user_database.dart';
import '../../../support/persisted_warnings.dart';

class _UnusedDeckCoverStore implements DeckCoverStorePort {
  @override
  Future<void> updateDeckCoverPath(String deckId, String localPath) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late List<String> warnings;
  late ForegroundEnrichmentRunner Function(
    Future<void> Function() onPassFinished,
  )
  createRunner;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    warnings = recordPersistedWarnings();
    database = await openInMemoryUserDatabase();
    final claims = EnrichmentWorkClaimRepository(database);
    final outcomes = EnrichmentWorkOutcomeRepository(database);
    final ownership = EnrichmentOwnershipRepository(database);

    // One species waiting for its reference image, whose lookup fails on a
    // real database error: the pass fails in BaseWorker's claim loop. The
    // cover and iNaturalist queues stay empty.
    await ownership.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-1': {'sp-a'},
      },
      prioritizedDeckIds: ['deck-1'],
    );
    final speciesRepository = MockSpeciesRepository();
    when(speciesRepository.getSpecies(any)).thenAnswer((_) async {
      await database.rawQuery('SELECT * FROM no_such_table');
      return <Species>{};
    });

    createRunner = (onPassFinished) => ForegroundEnrichmentRunner(
      coverRunner: CoverJobRunner(
        EnrichmentJobRepository(database),
        _UnusedDeckCoverStore(),
        MockImageService(),
      ),
      baseWorker: BaseWorker(
        MockBaseImageEnrichmentService(),
        claims,
        outcomes,
        speciesRepository,
      ),
      iNatWorker: INatWorker(
        MockINatPhotoEnrichmentService(),
        MockSpeciesCommonNameEnrichmentService(),
        MockTaxonomyCommonNameEnrichmentService(),
        claims,
        outcomes,
        ownership,
        MockINatPhotoCacheRepository(),
        deckMembershipLock: DeckMembershipLock(),
      ),
      owner: 'test-owner',
      shouldStop: () => false,
      onProgress: () {},
      onPassFinished: onPassFinished,
    );
  });

  tearDown(() async {
    await database.close();
  });

  final passFailure = isA<DatabaseException>().having(
    (e) => e.isNoSuchTableError('no_such_table'),
    'isNoSuchTableError',
    isTrue,
  );

  test('a failed pass keeps its own error when finishing it fails as well, '
      'and logs the second one as a warning with its stack trace', () async {
    final runner = createRunner(() async => throw StateError('finish failed'));

    runner.start();

    await expectLater(runner.awaitIdle(), throwsA(passFailure));
    expect(runner.isRunning, isFalse);
    expect(warnings, hasLength(1));
    expect(
      warnings.single,
      startsWith(
        '[ForegroundEnrichmentRunner] Finishing a failed enrichment pass '
        'failed as well — StateError: Bad state: finish failed',
      ),
    );
    expect(warnings.single, contains('\n    #0 '));
  });

  test('a failed pass keeps its own error without a warning when the '
      'database is closed by the time it is finished', () async {
    final closed = await closedDatabaseException();
    final runner = createRunner(() => Future.error(closed));

    runner.start();

    await expectLater(runner.awaitIdle(), throwsA(passFailure));
    expect(warnings, isEmpty);
  });

  test('finishing a pass that succeeded still propagates its own '
      'failure', () async {
    await database.delete(EnrichmentWorkTables.capabilityState);
    final runner = createRunner(() async => throw StateError('finish failed'));

    runner.start();

    await expectLater(runner.awaitIdle(), throwsA(isA<StateError>()));
    expect(warnings, isEmpty);
  });
}
