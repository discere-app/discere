import 'dart:convert';

import 'package:discere/enrichment/pipeline/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/pipeline/model/inat_work_item.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
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
      expect(speciesRows.single['deck_count'], 1);

      final membershipRows = await database.query(
        EnrichmentWorkRepository.deckMembershipTable,
        where: 'species_id = ?',
        whereArgs: ['sp-b'],
      );
      expect(membershipRows.map((row) => row['deck_id']), ['deck-1']);

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
    expect(third.taxonomyRuntimeEntityKey, 'genus:acropora');
    expect(third.taxonomySpeciesIds, {'sp-a'});
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

  group('loadDeckProjection', () {
    test('computes image completeness correctly under reactive seeding, '
        'including a species owned by another deck via membership', () async {
      // A single assignSpeciesOwners call carrying deck-1's full species set
      // (sp-a, sp-b, sp-c) plus deck-2 sharing sp-c — matches how real
      // callers always pass a deck's complete current species set rather
      // than incremental slices (assignSpeciesOwners prunes species missing
      // from the call's input for decks it's given, so calling it
      // repeatedly with only one species at a time for the same deck would
      // otherwise delete the ones from earlier calls).
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-2': {'sp-c'},
          'deck-1': {'sp-a', 'sp-b', 'sp-c'},
        },
        prioritizedDeckIds: ['deck-2', 'deck-1'],
      );

      // sp-a: base done outright, no inatPrimary row -> complete, has image.
      await repository.markCapabilityTerminal(
        'sp-a',
        EnrichmentStage.base,
        'done',
      );

      // sp-b: base noResult, inatPrimary done -> complete, has image.
      await repository.markCapabilityTerminal(
        'sp-b',
        EnrichmentStage.base,
        'noResult',
      );
      await repository.seedCapability(
        'sp-b',
        EnrichmentStage.inatPrimary,
        priorityTier: 10,
      );
      await repository.markCapabilityTerminal(
        'sp-b',
        EnrichmentStage.inatPrimary,
        'done',
      );

      // sp-c: owned by deck-2 for cross-deck dedup, but also referenced by
      // deck-1 via membership -> must still be included in deck-1's
      // projection regardless of ownership.
      await repository.markCapabilityTerminal(
        'sp-c',
        EnrichmentStage.base,
        'done',
      );

      final projection = await repository.loadDeckProjection('deck-1');

      expect(projection.speciesCount, 3);
      expect(projection.imageCompleteSpeciesCount, 3);
      expect(projection.imageDoneSpeciesCount, 3);
      expect(projection.imageStagesComplete, isTrue);
      expect(projection.hasAnyImage, isTrue);
    });

    test(
      'a species still waiting on inatPrimary keeps the deck incomplete',
      () async {
        await repository.assignSpeciesOwners(
          speciesIdsByDeckId: {
            'deck-1': {'sp-a'},
          },
          prioritizedDeckIds: ['deck-1'],
        );
        await repository.markCapabilityTerminal(
          'sp-a',
          EnrichmentStage.base,
          'noResult',
        );
        await repository.seedCapability(
          'sp-a',
          EnrichmentStage.inatPrimary,
          priorityTier: 10,
        );

        final projection = await repository.loadDeckProjection('deck-1');

        expect(projection.imageStagesComplete, isFalse);
        expect(projection.hasAnyImage, isFalse);
      },
    );

    test('a species confirmed to have no image anywhere is image-complete but '
        'not counted as having an image', () async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-1'],
      );
      await repository.markCapabilityTerminal(
        'sp-a',
        EnrichmentStage.base,
        'noResult',
      );
      await repository.seedCapability(
        'sp-a',
        EnrichmentStage.inatPrimary,
        priorityTier: 10,
      );
      await repository.markCapabilityTerminal(
        'sp-a',
        EnrichmentStage.inatPrimary,
        'noResult',
      );

      final projection = await repository.loadDeckProjection('deck-1');

      expect(projection.imageStagesComplete, isTrue);
      expect(projection.hasAnyImage, isFalse);
    });

    test('counts species-common-names and backfill only for species that '
        'actually have those capabilities seeded', () async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a', 'sp-b'},
        },
        prioritizedDeckIds: ['deck-1'],
        includeCommonNamesByDeckId: {'deck-1': true},
      );
      await repository.markCapabilityTerminal(
        'sp-a',
        EnrichmentStage.names,
        'done',
      );
      // sp-b's speciesCommonNames stays pending.
      await repository.seedCapability(
        'sp-a',
        EnrichmentStage.inatBackfill,
        priorityTier: 40,
      );
      await repository.markCapabilityTerminal(
        'sp-a',
        EnrichmentStage.inatBackfill,
        'done',
      );

      final projection = await repository.loadDeckProjection('deck-1');

      expect(projection.speciesCommonNamesWantedCount, 2);
      expect(projection.speciesCommonNamesTerminalCount, 1);
      expect(projection.inatBackfillWantedCount, 1);
      expect(projection.inatBackfillTerminalCount, 1);
    });

    test(
      'counts taxonomy items relevant to the deck via deck_ids_json, and '
      'surfaces permanent failures from either species or taxonomy work',
      () async {
        await repository.assignSpeciesOwners(
          speciesIdsByDeckId: {
            'deck-1': {'sp-a'},
          },
          prioritizedDeckIds: ['deck-1'],
        );
        await repository.assignTaxonomyOwners(
          deckId: 'deck-1',
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
        await repository.markTaxonomyCapabilityTerminal(
          'genus:acropora',
          'done',
        );
        // Unrelated taxonomy item for a different deck only — must not count.
        await repository.assignTaxonomyOwners(
          deckId: 'deck-2',
          items: [
            const TaxonomyWorkPlanItem(
              workKey: 'genus:other',
              runtimeEntityKey: 'genus:other',
              rank: 'genus',
              scientificName: 'Other',
              speciesIds: {'sp-z'},
            ),
          ],
        );

        var projection = await repository.loadDeckProjection('deck-1');
        expect(projection.taxonomyTotalCount, 1);
        expect(projection.taxonomyTerminalCount, 1);
        expect(projection.anyPermanentFailure, isFalse);

        await repository.recordCapabilityAttemptFailure(
          'sp-a',
          EnrichmentStage.base,
          maxAttempts: 1,
          backoffSteps: const [Duration(seconds: 1)],
        );
        projection = await repository.loadDeckProjection('deck-1');
        expect(projection.anyPermanentFailure, isTrue);
      },
    );

    test(
      'a deck with no tracked species returns an empty-shaped projection',
      () async {
        final projection = await repository.loadDeckProjection('deck-none');

        expect(projection.speciesCount, 0);
        expect(projection.imageStagesComplete, isFalse);
        expect(projection.hasAnyImage, isFalse);
      },
    );
  });

  group('loadDeckIdsUpdatedSince', () {
    test('returns decks with changes across capability (via membership), '
        'taxonomy, and unresolved-name tables', () async {
      final threshold = DateTime.now().millisecondsSinceEpoch;

      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-1'],
      );

      await database.insert(EnrichmentWorkRepository.taxonomyWorkTable, {
        'work_key': 'genus:acropora',
        'runtime_entity_key': 'genus:acropora',
        'owner_deck_id': 'deck-2',
        'deck_ids_json': jsonEncode(['deck-2']),
        'species_ids_json': jsonEncode(['sp-z']),
        'rank': 'genus',
        'scientific_name': 'Acropora',
        'common_names_state': 'pending',
        'attempt_count': 0,
        'updated_at': threshold + 1000,
      });

      await database.insert(EnrichmentWorkRepository.unresolvedNamesTable, {
        'deck_id': 'deck-3',
        'name': 'Unknownus fishus',
        'state': 'pending',
        'wants_inat_photos': 1,
        'wants_common_names': 1,
        'attempt_count': 0,
        'updated_at': threshold + 1000,
      });

      final changedDeckIds = await repository.loadDeckIdsUpdatedSince(
        threshold - 1,
      );
      expect(changedDeckIds, {'deck-1', 'deck-2', 'deck-3'});

      final future = threshold + 10000;
      expect(await repository.loadDeckIdsUpdatedSince(future), isEmpty);
    });
  });

  group('loadSpeciesIdsWithoutImage', () {
    test(
      'lists only species whose image stages are terminal without ever '
      'landing an image, excluding species still in progress or with one',
      () async {
        await repository.assignSpeciesOwners(
          speciesIdsByDeckId: {
            'deck-1': {'sp-none', 'sp-has-image', 'sp-in-progress'},
          },
          prioritizedDeckIds: ['deck-1'],
        );

        // sp-none: base and inatPrimary both terminal, neither done.
        await repository.markCapabilityTerminal(
          'sp-none',
          EnrichmentStage.base,
          'noResult',
        );
        await repository.seedCapability(
          'sp-none',
          EnrichmentStage.inatPrimary,
          priorityTier: 10,
        );
        await repository.markCapabilityTerminal(
          'sp-none',
          EnrichmentStage.inatPrimary,
          'noResult',
        );

        // sp-has-image: base succeeded outright.
        await repository.markCapabilityTerminal(
          'sp-has-image',
          EnrichmentStage.base,
          'done',
        );

        // sp-in-progress: still waiting on inatPrimary.
        await repository.markCapabilityTerminal(
          'sp-in-progress',
          EnrichmentStage.base,
          'noResult',
        );
        await repository.seedCapability(
          'sp-in-progress',
          EnrichmentStage.inatPrimary,
          priorityTier: 10,
        );

        final withoutImage = await repository.loadSpeciesIdsWithoutImage(
          'deck-1',
        );

        expect(withoutImage, {'sp-none'});
      },
    );
  });

  group('loadPermanentlyUnresolvedNames', () {
    test(
      'returns only names that gave up permanently for the given deck',
      () async {
        await database.insert(EnrichmentWorkRepository.unresolvedNamesTable, {
          'deck_id': 'deck-1',
          'name': 'Ghostus fishus',
          'state': 'permanentFailure',
          'wants_inat_photos': 1,
          'wants_common_names': 1,
          'attempt_count': 5,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });
        await database.insert(EnrichmentWorkRepository.unresolvedNamesTable, {
          'deck_id': 'deck-1',
          'name': 'Pendingus fishus',
          'state': 'retryScheduled',
          'wants_inat_photos': 1,
          'wants_common_names': 1,
          'attempt_count': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });
        await database.insert(EnrichmentWorkRepository.unresolvedNamesTable, {
          'deck_id': 'deck-2',
          'name': 'Otherdeck fishus',
          'state': 'permanentFailure',
          'wants_inat_photos': 1,
          'wants_common_names': 1,
          'attempt_count': 5,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });

        final names = await repository.loadPermanentlyUnresolvedNames('deck-1');

        expect(names, ['Ghostus fishus']);
      },
    );
  });
}
