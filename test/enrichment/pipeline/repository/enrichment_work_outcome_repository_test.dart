import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/base_image_fallback_reason.dart';
import 'package:discere/enrichment/pipeline/model/base_image_retry_policy.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_outcome_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

/// How an attempt on a claimed item is recorded: terminal, retried, or
/// given up on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentOwnershipRepository repository;
  late EnrichmentWorkOutcomeRepository outcomes;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    repository = EnrichmentOwnershipRepository(database);
    outcomes = EnrichmentWorkOutcomeRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('seedCapability is idempotent and does not reset an already-terminal '
      'capability back to pending', () async {
    // inatPrimary/inatBackfill are consent-gated on wants_inat_photos — grant
    // it via assignSpeciesOwners first so the direct seedCapability calls
    // below actually create a row.
    await repository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-1': {'sp-a'},
      },
      prioritizedDeckIds: ['deck-1'],
      includeInatPhotosByDeckId: {'deck-1': true},
    );
    await outcomes.seedCapability(
      'sp-a',
      EnrichmentCapability.inatPrimary,
      priorityTier: 10,
    );
    await outcomes.markCapabilityTerminal(
      'sp-a',
      EnrichmentCapability.inatPrimary,
      EnrichmentWorkState.done,
    );

    await outcomes.seedCapability(
      'sp-a',
      EnrichmentCapability.inatPrimary,
      priorityTier: 10,
    );

    final rows = await database.query(
      EnrichmentWorkTables.capabilityState,
      where: 'species_id = ? AND capability = ?',
      whereArgs: ['sp-a', 'inatPrimary'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['state'], 'done');
  });
  test('recordCapabilityAttemptFailure schedules a backoff retry, then gives '
      'up once maxAttempts is reached', () async {
    // inatPrimary/inatBackfill are consent-gated on wants_inat_photos — grant
    // it via assignSpeciesOwners first so the direct seedCapability call
    // below actually creates a row.
    await repository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-1': {'sp-a'},
      },
      prioritizedDeckIds: ['deck-1'],
      includeInatPhotosByDeckId: {'deck-1': true},
    );
    await outcomes.seedCapability(
      'sp-a',
      EnrichmentCapability.inatPrimary,
      priorityTier: 10,
    );

    final firstGaveUp = await outcomes.recordCapabilityAttemptFailure(
      'sp-a',
      EnrichmentCapability.inatPrimary,
      maxAttempts: 2,
      backoffSteps: const [Duration(seconds: 15), Duration(seconds: 30)],
      error: 'timeout',
      failureKind: 'temporary',
    );
    expect(firstGaveUp, isFalse);

    var rows = await database.query(
      EnrichmentWorkTables.capabilityState,
      where: 'species_id = ? AND capability = ?',
      whereArgs: ['sp-a', 'inatPrimary'],
    );
    expect(rows.single['state'], 'retryScheduled');
    expect(rows.single['attempt_count'], 1);
    expect(rows.single['next_attempt_at'], isNotNull);

    final secondGaveUp = await outcomes.recordCapabilityAttemptFailure(
      'sp-a',
      EnrichmentCapability.inatPrimary,
      maxAttempts: 2,
      backoffSteps: const [Duration(seconds: 15), Duration(seconds: 30)],
      error: 'timeout',
      failureKind: 'temporary',
    );
    expect(secondGaveUp, isTrue);

    rows = await database.query(
      EnrichmentWorkTables.capabilityState,
      where: 'species_id = ? AND capability = ?',
      whereArgs: ['sp-a', 'inatPrimary'],
    );
    expect(rows.single['state'], 'permanentFailure');
    expect(rows.single['attempt_count'], 2);
    expect(rows.single['next_attempt_at'], isNull);
  });

  test('markCapabilityTerminal stamps reference_db_version when given, leaves '
      'it null when omitted', () async {
    await repository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-1': {'sp-a', 'sp-b'},
      },
      prioritizedDeckIds: ['deck-1'],
    );

    await outcomes.markCapabilityTerminal(
      'sp-a',
      EnrichmentCapability.base,
      EnrichmentWorkState.done,
      referenceDbVersion: 7,
    );
    await outcomes.markCapabilityTerminal(
      'sp-b',
      EnrichmentCapability.base,
      EnrichmentWorkState.done,
    );

    final rows = await database.query(
      EnrichmentWorkTables.capabilityState,
      where: "capability = 'base'",
      orderBy: 'species_id',
    );
    expect(rows.map((r) => r['species_id']), ['sp-a', 'sp-b']);
    expect(rows[0]['reference_db_version'], 7);
    expect(rows[1]['reference_db_version'], isNull);
  });

  test('markTaxonomyCapabilityTerminal is unaffected by the new '
      'reference_db_version param (different table, never passed)', () async {
    await repository.registerTaxonomyWork(
      items: [
        const TaxonomyWorkPlanItem(
          workKey: 'genus:acropora',
          runtimeEntityKey: 'genus:acropora',
          rank: 'genus',
          scientificName: 'Acropora',
          speciesIds: {'sp-a'},
        ),
      ],
    );

    await outcomes.markTaxonomyCapabilityTerminal('genus:acropora', EnrichmentWorkState.done);

    final rows = await database.query(
      EnrichmentWorkTables.taxonomyWork,
    );
    expect(rows.single['common_names_state'], 'done');
  });

  group('recordBaseImageAttemptFailure', () {
    setUp(() async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-1'],
      );
    });

    Future<bool> fail({
      BaseImageFallbackReason reason = BaseImageFallbackReason.hostUnavailable,
      String? host = 'www.fishbase.se',
    }) => outcomes.recordBaseImageAttemptFailure(
      'sp-a',
      reason: reason,
      host: host,
      error: 'failed',
      failureKind: 'temporary',
      referenceDbVersion: 7,
    );

    Future<Map<String, Object?>> baseRow() async => (await database.query(
      EnrichmentWorkTables.capabilityState,
      where: "species_id = 'sp-a' AND capability = 'base'",
    )).single;

    test('falls back with the last short attempt only, and gives up after '
        'the long phase with the reference-DB version stamped', () async {
      final fallsBack = [for (var i = 0; i < 5; i++) await fail()];

      expect(fallsBack, [false, true, false, false, false]);
      final row = await baseRow();
      expect(row['state'], 'permanentFailure');
      expect(row['attempt_count'], BaseImageRetryPolicy.maxAttempts);
      expect(row['reference_db_version'], 7);
    });

    test('stamps no reference-DB version while it still retries', () async {
      await fail();
      await fail();

      expect((await baseRow())['reference_db_version'], isNull);
    });

    test('marks the fallback, and a failure in the long phase leaves the '
        'marking as it was', () async {
      await fail();
      expect((await baseRow())['fallback_reason'], isNull);

      await fail(host: 'www.fishbase.se');
      final marked = await baseRow();
      expect(marked['fallback_reason'], 'hostUnavailable');
      expect(marked['fallback_host'], 'www.fishbase.se');
      expect(marked['fallback_at'], isNotNull);

      await fail(reason: BaseImageFallbackReason.hostBlocked, host: 'x.org');
      final later = await baseRow();
      expect(later['fallback_reason'], 'hostUnavailable');
      expect(later['fallback_host'], 'www.fishbase.se');
      expect(later['fallback_at'], marked['fallback_at']);
    });

    test('a missing image falls back and gives up with the first '
        'failure', () async {
      final fallsBack = await fail(
        reason: BaseImageFallbackReason.imageMissing,
      );

      expect(fallsBack, isTrue);
      final row = await baseRow();
      expect(row['state'], 'permanentFailure');
      expect(row['reference_db_version'], 7);
      expect(row['fallback_reason'], 'imageMissing');
    });

    test('the marking outlives a later success, and the next fallback '
        'overwrites it', () async {
      await fail();
      await fail();
      await outcomes.markCapabilityTerminal(
        'sp-a',
        EnrichmentCapability.base,
        EnrichmentWorkState.done,
      );
      final succeeded = await baseRow();
      expect(succeeded['state'], 'done');
      expect(succeeded['fallback_reason'], 'hostUnavailable');
      expect(succeeded['fallback_host'], 'www.fishbase.se');

      await fail(reason: BaseImageFallbackReason.imageMissing, host: 'a.org');

      final refallen = await baseRow();
      expect(refallen['fallback_reason'], 'imageMissing');
      expect(refallen['fallback_host'], 'a.org');
    });
  });
}
