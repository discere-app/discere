import 'dart:convert';

import 'package:discere/enrichment/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/model/inat_work_item.dart';
import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/repository/enrichment_work_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentWorkRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await openDatabase(inMemoryDatabasePath, version: 1);
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_species_work.sql',
      ),
    );
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_taxonomy_work.sql',
      ),
    );
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_species_capability_state.sql',
      ),
    );
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_species_deck_membership.sql',
      ),
    );
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_unresolved_names.sql',
      ),
    );
    repository = EnrichmentWorkRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'assignSpeciesOwners keeps overlapping species on a single owner deck',
    () async {
      final assignments = await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a', 'sp-b'},
          'deck-2': {'sp-b', 'sp-c'},
        },
        prioritizedDeckIds: ['deck-1', 'deck-2'],
      );

      expect(assignments['deck-1'], ['sp-b', 'sp-a']);
      expect(assignments['deck-2'], ['sp-c']);
    },
  );

  test(
    'assignSpeciesOwners preserves active deck owner across mid-flight import',
    () async {
      // T=0: deck-active already running with overlapping species.
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-active': {'sp-shared', 'sp-active-only'},
        },
        prioritizedDeckIds: ['deck-active'],
      );

      // T=1: a new deck is imported. The caller passes deck-active at lower
      // priority so the resolver knows it is still in flight.
      final assignments = await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-new': {'sp-shared', 'sp-new-only'},
          'deck-active': {'sp-shared', 'sp-active-only'},
        },
        prioritizedDeckIds: ['deck-new', 'deck-active'],
      );

      // sp-shared stays owned by the active deck — no duplicate work.
      expect(assignments['deck-new'], ['sp-new-only']);
      expect(
        assignments['deck-active'],
        containsAll(['sp-shared', 'sp-active-only']),
      );
    },
  );

  test(
    'loadSucceededSpeciesIdsForStage returns species marked succeeded',
    () async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a', 'sp-b', 'sp-c'},
        },
        prioritizedDeckIds: ['deck-1'],
      );

      await repository.markSpeciesStageCompleted(
        stage: EnrichmentStage.base,
        speciesIds: {'sp-a', 'sp-c'},
      );

      final succeeded = await repository.loadSucceededSpeciesIdsForStage(
        EnrichmentStage.base,
      );
      expect(succeeded, {'sp-a', 'sp-c'});

      final otherStage = await repository.loadSucceededSpeciesIdsForStage(
        EnrichmentStage.inatPrimary,
      );
      expect(otherStage, isEmpty);
    },
  );

  test('markSpeciesStageCompleted persists per-stage species state', () async {
    await repository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-1': {'sp-a'},
      },
      prioritizedDeckIds: ['deck-1'],
    );

    await repository.markSpeciesStageCompleted(
      stage: EnrichmentStage.inatPrimary,
      speciesIds: {'sp-a'},
    );

    final rows = await database.query(
      EnrichmentWorkRepository.speciesWorkTable,
      where: 'species_id = ?',
      whereArgs: ['sp-a'],
    );

    expect(rows, hasLength(1));
    expect(rows.single['inat_primary_state'], 'succeeded');
  });

  test('assignTaxonomyOwners preserves the first owner across decks', () async {
    final item = TaxonomyWorkPlanItem(
      workKey: 'genus:taxon:1',
      runtimeEntityKey: 'genus:acropora',
      rank: 'genus',
      scientificName: 'Acropora',
      speciesIds: {'sp-a', 'sp-b'},
    );

    final firstOwnerItems = await repository.assignTaxonomyOwners(
      deckId: 'deck-1',
      items: [item],
    );
    final secondOwnerItems = await repository.assignTaxonomyOwners(
      deckId: 'deck-2',
      items: [
        TaxonomyWorkPlanItem(
          workKey: 'genus:taxon:1',
          runtimeEntityKey: 'genus:acropora',
          rank: 'genus',
          scientificName: 'Acropora',
          speciesIds: {'sp-c'},
        ),
      ],
    );

    expect(firstOwnerItems, hasLength(1));
    expect(secondOwnerItems, isEmpty);

    final rows = await database.query(
      EnrichmentWorkRepository.taxonomyWorkTable,
      where: 'runtime_entity_key = ?',
      whereArgs: ['genus:acropora'],
    );

    expect(rows, hasLength(1));
    expect(rows.single['owner_deck_id'], 'deck-1');
    expect(
      (jsonDecode(rows.single['deck_ids_json']! as String) as List<dynamic>)
          .cast<String>(),
      ['deck-1', 'deck-2'],
    );
    expect(
      (jsonDecode(rows.single['species_ids_json']! as String) as List<dynamic>)
          .cast<String>(),
      ['sp-a', 'sp-b', 'sp-c'],
    );
  });

  test(
    'releaseDeck removes deleted deck from stored species and taxonomy work',
    () async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a', 'sp-b'},
          'deck-2': {'sp-b'},
        },
        prioritizedDeckIds: ['deck-1', 'deck-2'],
      );

      await repository.assignTaxonomyOwners(
        deckId: 'deck-1',
        items: [
          TaxonomyWorkPlanItem(
            workKey: 'genus:taxon:1',
            runtimeEntityKey: 'genus:acropora',
            rank: 'genus',
            scientificName: 'Acropora',
            speciesIds: {'sp-a', 'sp-b'},
          ),
        ],
      );
      await repository.assignTaxonomyOwners(
        deckId: 'deck-2',
        items: [
          TaxonomyWorkPlanItem(
            workKey: 'genus:taxon:1',
            runtimeEntityKey: 'genus:acropora',
            rank: 'genus',
            scientificName: 'Acropora',
            speciesIds: {'sp-b'},
          ),
        ],
      );

      await repository.releaseDeck('deck-2');

      final speciesRows = await database.query(
        EnrichmentWorkRepository.speciesWorkTable,
        where: 'species_id = ?',
        whereArgs: ['sp-b'],
      );
      expect(speciesRows, hasLength(1));
      expect(
        (jsonDecode(speciesRows.single['deck_ids_json']! as String)
                as List<dynamic>)
            .cast<String>(),
        ['deck-1'],
      );

      final taxonomyRows = await database.query(
        EnrichmentWorkRepository.taxonomyWorkTable,
        where: 'runtime_entity_key = ?',
        whereArgs: ['genus:acropora'],
      );
      expect(taxonomyRows, hasLength(1));
      expect(
        (jsonDecode(taxonomyRows.single['deck_ids_json']! as String)
                as List<dynamic>)
            .cast<String>(),
        ['deck-1'],
      );
    },
  );

  test('assignSpeciesOwners ORs consent across decks and seeds capability rows '
      'accordingly', () async {
    await repository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-a': {'sp-shared'},
      },
      prioritizedDeckIds: ['deck-a'],
      includeInatPhotosByDeckId: {'deck-a': true},
      includeCommonNamesByDeckId: {'deck-a': false},
    );
    await repository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-a': {'sp-shared'},
        'deck-b': {'sp-shared'},
      },
      prioritizedDeckIds: ['deck-a', 'deck-b'],
      includeInatPhotosByDeckId: {'deck-a': true, 'deck-b': false},
      includeCommonNamesByDeckId: {'deck-a': false, 'deck-b': false},
    );

    final rows = await database.query(
      EnrichmentWorkRepository.speciesWorkTable,
      where: 'species_id = ?',
      whereArgs: ['sp-shared'],
    );
    expect(rows.single['wants_inat_photos'], 1);
    expect(rows.single['wants_common_names'], 0);

    // base is always seeded; speciesCommonNames is not, since consent for
    // it never flipped true across either call.
    final capabilityRows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
      where: 'species_id = ?',
      whereArgs: ['sp-shared'],
    );
    expect(capabilityRows.map((r) => r['capability']), ['base']);

    final membershipRows = await database.query(
      EnrichmentWorkRepository.deckMembershipTable,
      where: 'species_id = ?',
      whereArgs: ['sp-shared'],
      orderBy: 'deck_id',
    );
    expect(membershipRows.map((r) => r['deck_id']), ['deck-a', 'deck-b']);
  });

  test('assignSpeciesOwners consent is additive-only: a later opt-out does not '
      'revoke an earlier opt-in', () async {
    await repository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-a': {'sp-shared'},
      },
      prioritizedDeckIds: ['deck-a'],
      includeCommonNamesByDeckId: {'deck-a': true},
    );
    await repository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-a': {'sp-shared'},
      },
      prioritizedDeckIds: ['deck-a'],
      includeCommonNamesByDeckId: {'deck-a': false},
    );

    final rows = await database.query(
      EnrichmentWorkRepository.speciesWorkTable,
      where: 'species_id = ?',
      whereArgs: ['sp-shared'],
    );
    expect(rows.single['wants_common_names'], 1);

    final capabilityRows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
      where: 'species_id = ? AND capability = ?',
      whereArgs: ['sp-shared', 'speciesCommonNames'],
    );
    expect(capabilityRows, hasLength(1));
  });

  test('seedCapability is idempotent and does not reset an already-terminal '
      'capability back to pending', () async {
    await repository.seedCapability(
      'sp-a',
      EnrichmentStage.inatPrimary,
      priorityTier: 10,
    );
    await repository.markCapabilityTerminal(
      'sp-a',
      EnrichmentStage.inatPrimary,
      'done',
    );

    await repository.seedCapability(
      'sp-a',
      EnrichmentStage.inatPrimary,
      priorityTier: 10,
    );

    final rows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
      where: 'species_id = ? AND capability = ?',
      whereArgs: ['sp-a', 'inatPrimary'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['state'], 'done');
  });

  test('recordCapabilityAttemptFailure schedules a backoff retry, then gives '
      'up once maxAttempts is reached', () async {
    await repository.seedCapability(
      'sp-a',
      EnrichmentStage.inatPrimary,
      priorityTier: 10,
    );

    final firstGaveUp = await repository.recordCapabilityAttemptFailure(
      'sp-a',
      EnrichmentStage.inatPrimary,
      maxAttempts: 2,
      backoffSteps: const [Duration(seconds: 15), Duration(seconds: 30)],
      error: 'timeout',
      failureKind: 'temporary',
    );
    expect(firstGaveUp, isFalse);

    var rows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
      where: 'species_id = ? AND capability = ?',
      whereArgs: ['sp-a', 'inatPrimary'],
    );
    expect(rows.single['state'], 'retryScheduled');
    expect(rows.single['attempt_count'], 1);
    expect(rows.single['next_attempt_at'], isNotNull);

    final secondGaveUp = await repository.recordCapabilityAttemptFailure(
      'sp-a',
      EnrichmentStage.inatPrimary,
      maxAttempts: 2,
      backoffSteps: const [Duration(seconds: 15), Duration(seconds: 30)],
      error: 'timeout',
      failureKind: 'temporary',
    );
    expect(secondGaveUp, isTrue);

    rows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
      where: 'species_id = ? AND capability = ?',
      whereArgs: ['sp-a', 'inatPrimary'],
    );
    expect(rows.single['state'], 'permanentFailure');
    expect(rows.single['attempt_count'], 2);
    expect(rows.single['next_attempt_at'], isNull);
  });

  test('claimBaseWorkBatch claims pending species up to the limit and flips '
      'them to running so a later claim only sees what is left', () async {
    await repository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-1': {'sp-a', 'sp-b', 'sp-c'},
      },
      prioritizedDeckIds: ['deck-1'],
    );

    final claimed = await repository.claimBaseWorkBatch(limit: 2);
    expect(claimed, hasLength(2));

    final runningRows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
      where: "capability = 'base' AND state = 'running'",
    );
    expect(runningRows, hasLength(2));

    final secondClaim = await repository.claimBaseWorkBatch(limit: 5);
    expect(secondClaim, hasLength(1));
  });

  test('claimNextINatWorkItem drains the shared queue in priority order across '
      'species/taxonomy/unresolved-name sources', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.insert(EnrichmentWorkRepository.capabilityStateTable, {
      'species_id': 'sp-a',
      'capability': 'speciesCommonNames',
      'state': 'pending',
      'priority_tier': 20,
      'attempt_count': 0,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkRepository.capabilityStateTable, {
      'species_id': 'sp-b',
      'capability': 'inatPrimary',
      'state': 'pending',
      'priority_tier': 10,
      'attempt_count': 0,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkRepository.taxonomyWorkTable, {
      'work_key': 'genus:acropora',
      'runtime_entity_key': 'genus:acropora',
      'owner_deck_id': 'deck-1',
      'deck_ids_json': jsonEncode(['deck-1']),
      'species_ids_json': jsonEncode(['sp-a']),
      'rank': 'genus',
      'scientific_name': 'Acropora',
      'common_names_state': 'pending',
      'attempt_count': 0,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkRepository.unresolvedNamesTable, {
      'deck_id': 'deck-1',
      'name': 'Unknownus fishus',
      'state': 'pending',
      'attempt_count': 0,
      'updated_at': now,
    });

    // Priority order: inatPrimary (10) < speciesCommonNames (20) <
    // taxonomyCommonNames (30) < nameResolution (50).
    final first = await repository.claimNextINatWorkItem();
    expect(first!.kind, INatWorkItemKind.inatPrimary);
    expect(first.speciesId, 'sp-b');
    expect(first.priorityTier, 10);

    final second = await repository.claimNextINatWorkItem();
    expect(second!.kind, INatWorkItemKind.speciesCommonNames);
    expect(second.speciesId, 'sp-a');
    expect(second.priorityTier, 20);

    final third = await repository.claimNextINatWorkItem();
    expect(third!.kind, INatWorkItemKind.taxonomyCommonNames);
    expect(third.taxonomyWorkKey, 'genus:acropora');
    expect(third.priorityTier, 30);

    final fourth = await repository.claimNextINatWorkItem();
    expect(fourth!.kind, INatWorkItemKind.nameResolution);
    expect(fourth.deckId, 'deck-1');
    expect(fourth.unresolvedName, 'Unknownus fishus');
    expect(fourth.priorityTier, 50);

    expect(await repository.claimNextINatWorkItem(), isNull);
  });

  test('clearRetryAttemptForRetryScheduledWorkItems clears next_attempt_at '
      'across all three queue tables', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final future = now + 60000;
    await database.insert(EnrichmentWorkRepository.capabilityStateTable, {
      'species_id': 'sp-a',
      'capability': 'inatPrimary',
      'state': 'retryScheduled',
      'priority_tier': 10,
      'attempt_count': 1,
      'next_attempt_at': future,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkRepository.taxonomyWorkTable, {
      'work_key': 'genus:acropora',
      'runtime_entity_key': 'genus:acropora',
      'owner_deck_id': 'deck-1',
      'deck_ids_json': jsonEncode(['deck-1']),
      'species_ids_json': jsonEncode(['sp-a']),
      'rank': 'genus',
      'scientific_name': 'Acropora',
      'common_names_state': 'retryScheduled',
      'attempt_count': 1,
      'next_attempt_at': future,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkRepository.unresolvedNamesTable, {
      'deck_id': 'deck-1',
      'name': 'Unknownus fishus',
      'state': 'retryScheduled',
      'attempt_count': 1,
      'next_attempt_at': future,
      'updated_at': now,
    });

    final cleared = await repository
        .clearRetryAttemptForRetryScheduledWorkItems();
    expect(cleared, 3);

    final capabilityRows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
    );
    expect(capabilityRows.single['next_attempt_at'], isNull);
    final taxonomyRows = await database.query(
      EnrichmentWorkRepository.taxonomyWorkTable,
    );
    expect(taxonomyRows.single['next_attempt_at'], isNull);
    final unresolvedRows = await database.query(
      EnrichmentWorkRepository.unresolvedNamesTable,
    );
    expect(unresolvedRows.single['next_attempt_at'], isNull);
  });

  test('recoverInterruptedWork reverts running rows back to pending across all '
      'three queue tables', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.insert(EnrichmentWorkRepository.capabilityStateTable, {
      'species_id': 'sp-a',
      'capability': 'base',
      'state': 'running',
      'priority_tier': 0,
      'attempt_count': 0,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkRepository.taxonomyWorkTable, {
      'work_key': 'genus:acropora',
      'runtime_entity_key': 'genus:acropora',
      'owner_deck_id': 'deck-1',
      'deck_ids_json': jsonEncode(['deck-1']),
      'species_ids_json': jsonEncode(['sp-a']),
      'rank': 'genus',
      'scientific_name': 'Acropora',
      'common_names_state': 'running',
      'attempt_count': 0,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkRepository.unresolvedNamesTable, {
      'deck_id': 'deck-1',
      'name': 'Unknownus fishus',
      'state': 'running',
      'attempt_count': 0,
      'updated_at': now,
    });

    await repository.recoverInterruptedWork();

    final capabilityRows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
    );
    expect(capabilityRows.single['state'], 'pending');
    final taxonomyRows = await database.query(
      EnrichmentWorkRepository.taxonomyWorkTable,
    );
    expect(taxonomyRows.single['common_names_state'], 'pending');
    final unresolvedRows = await database.query(
      EnrichmentWorkRepository.unresolvedNamesTable,
    );
    expect(unresolvedRows.single['state'], 'pending');
  });

  test(
    'pruneSpeciesMembershipIfFullyTerminal removes membership rows once '
    'every capability is terminal, but keeps the capability-state cache',
    () async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-1'],
        includeCommonNamesByDeckId: {'deck-1': false},
      );

      // Only 'base' was seeded (no common-names consent) — not yet terminal.
      await repository.pruneSpeciesMembershipIfFullyTerminal('sp-a');
      var membershipRows = await database.query(
        EnrichmentWorkRepository.deckMembershipTable,
        where: 'species_id = ?',
        whereArgs: ['sp-a'],
      );
      expect(membershipRows, hasLength(1));

      await repository.markCapabilityTerminal(
        'sp-a',
        EnrichmentStage.base,
        'done',
      );
      await repository.pruneSpeciesMembershipIfFullyTerminal('sp-a');

      membershipRows = await database.query(
        EnrichmentWorkRepository.deckMembershipTable,
        where: 'species_id = ?',
        whereArgs: ['sp-a'],
      );
      expect(membershipRows, isEmpty);

      final capabilityRows = await database.query(
        EnrichmentWorkRepository.capabilityStateTable,
        where: 'species_id = ?',
        whereArgs: ['sp-a'],
      );
      expect(capabilityRows, hasLength(1));
      expect(capabilityRows.single['state'], 'done');
    },
  );
}
