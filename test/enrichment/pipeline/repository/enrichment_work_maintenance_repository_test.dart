import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_maintenance_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_outcome_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

/// The operational resets: refreshing stale reference images, re-triggering
/// a deck, recovering after a crash, abandoning everything outstanding.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentOwnershipRepository repository;
  late EnrichmentWorkMaintenanceRepository maintenance;
  late EnrichmentWorkOutcomeRepository outcomes;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    repository = EnrichmentOwnershipRepository(database);
    maintenance = EnrichmentWorkMaintenanceRepository(database);
    outcomes = EnrichmentWorkOutcomeRepository(database);
  });

  tearDown(() async {
    await database.close();
  });
  group('resetStaleBaseCapability / countStaleBaseSpecies', () {
    Future<void> seedBaseTerminal(
      String speciesId,
      String deckId, {
      required EnrichmentWorkState state,
      int? referenceDbVersion,
    }) async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          deckId: {speciesId},
        },
        prioritizedDeckIds: [deckId],
      );
      await outcomes.markCapabilityTerminal(
        speciesId,
        EnrichmentCapability.base,
        state,
        referenceDbVersion: referenceDbVersion,
      );
    }

    test('resets a done row with an older stamped version back to pending, '
        'clearing retry bookkeeping', () async {
      await seedBaseTerminal(
        'sp-a',
        'deck-1',
        state: EnrichmentWorkState.done,
        referenceDbVersion: 5,
      );
      // Directly dirty the base row's retry bookkeeping to prove it's reset.
      await database.update(
        EnrichmentWorkTables.capabilityState,
        {'attempt_count': 3, 'last_error': 'stale error'},
        where: "species_id = 'sp-a' AND capability = 'base'",
      );

      final resetCount = await maintenance.resetStaleBaseCapability(
        deckId: 'deck-1',
        currentReferenceDbVersion: 6,
      );
      expect(resetCount, 1);

      final row = (await database.query(
        EnrichmentWorkTables.capabilityState,
        where: "species_id = 'sp-a' AND capability = 'base'",
      )).single;
      expect(row['state'], 'pending');
      expect(row['attempt_count'], 0);
      expect(row['last_error'], isNull);
    });

    test('resets a noResult row the same way', () async {
      await seedBaseTerminal(
        'sp-a',
        'deck-1',
        state: EnrichmentWorkState.noResult,
        referenceDbVersion: 5,
      );

      final resetCount = await maintenance.resetStaleBaseCapability(
        deckId: 'deck-1',
        currentReferenceDbVersion: 6,
      );
      expect(resetCount, 1);
    });

    test('leaves a row alone whose stamped version is >= the current '
        'version', () async {
      await seedBaseTerminal(
        'sp-a',
        'deck-1',
        state: EnrichmentWorkState.done,
        referenceDbVersion: 6,
      );

      final resetCount = await maintenance.resetStaleBaseCapability(
        deckId: 'deck-1',
        currentReferenceDbVersion: 6,
      );
      expect(resetCount, 0);
    });

    test('treats a never-stamped (null) row as stale', () async {
      await seedBaseTerminal('sp-a', 'deck-1', state: EnrichmentWorkState.done);

      final resetCount = await maintenance.resetStaleBaseCapability(
        deckId: 'deck-1',
        currentReferenceDbVersion: 6,
      );
      expect(resetCount, 1);
    });

    test('leaves a permanentFailure row untouched', () async {
      await seedBaseTerminal(
        'sp-a',
        'deck-1',
        state: EnrichmentWorkState.done,
        referenceDbVersion: 1,
      );
      await database.update(
        EnrichmentWorkTables.capabilityState,
        {'state': 'permanentFailure'},
        where: "species_id = 'sp-a' AND capability = 'base'",
      );

      final resetCount = await maintenance.resetStaleBaseCapability(
        deckId: 'deck-1',
        currentReferenceDbVersion: 6,
      );
      expect(resetCount, 0);
    });

    test('deck-scoped reset only touches species referencing that deck', () async {
      await seedBaseTerminal(
        'sp-a',
        'deck-1',
        state: EnrichmentWorkState.done,
        referenceDbVersion: 1,
      );
      await seedBaseTerminal(
        'sp-b',
        'deck-2',
        state: EnrichmentWorkState.done,
        referenceDbVersion: 1,
      );

      final resetCount = await maintenance.resetStaleBaseCapability(
        deckId: 'deck-1',
        currentReferenceDbVersion: 6,
      );
      expect(resetCount, 1);

      final spB = (await database.query(
        EnrichmentWorkTables.capabilityState,
        where: "species_id = 'sp-b' AND capability = 'base'",
      )).single;
      expect(spB['state'], 'done');
    });

    test('global reset (no deckId) touches every deck, but skips species with '
        'no remaining deck membership', () async {
      await seedBaseTerminal(
        'sp-a',
        'deck-1',
        state: EnrichmentWorkState.done,
        referenceDbVersion: 1,
      );
      await seedBaseTerminal(
        'sp-b',
        'deck-2',
        state: EnrichmentWorkState.done,
        referenceDbVersion: 1,
      );
      // Orphan: deck-3 releases sp-c, leaving a permanent dedup-cache row
      // with no deck membership (mirrors releaseDeck's contract).
      await seedBaseTerminal(
        'sp-c',
        'deck-3',
        state: EnrichmentWorkState.done,
        referenceDbVersion: 1,
      );
      await repository.releaseDeck('deck-3');

      final resetCount = await maintenance.resetStaleBaseCapability(
        currentReferenceDbVersion: 6,
      );
      expect(resetCount, 2);

      final spC = (await database.query(
        EnrichmentWorkTables.capabilityState,
        where: "species_id = 'sp-c' AND capability = 'base'",
      )).single;
      expect(spC['state'], 'done');
    });

    test('countStaleBaseSpecies mirrors resetStaleBaseCapability\'s scoping '
        'without mutating anything', () async {
      await seedBaseTerminal(
        'sp-a',
        'deck-1',
        state: EnrichmentWorkState.done,
        referenceDbVersion: 1,
      );
      await seedBaseTerminal(
        'sp-b',
        'deck-2',
        state: EnrichmentWorkState.done,
        referenceDbVersion: 6,
      );

      expect(
        await maintenance.countStaleBaseSpecies(currentReferenceDbVersion: 6),
        1,
      );
      expect(
        await maintenance.countStaleBaseSpecies(
          deckId: 'deck-1',
          currentReferenceDbVersion: 6,
        ),
        1,
      );
      expect(
        await maintenance.countStaleBaseSpecies(
          deckId: 'deck-2',
          currentReferenceDbVersion: 6,
        ),
        0,
      );

      final row = (await database.query(
        EnrichmentWorkTables.capabilityState,
        where: "species_id = 'sp-a' AND capability = 'base'",
      )).single;
      expect(row['state'], 'done');
    });
  });

  group('resetBaseCapabilityForRetrigger', () {
    Future<void> seedBaseTerminal(
      String speciesId,
      String deckId, {
      required EnrichmentWorkState state,
    }) async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          deckId: {speciesId},
        },
        prioritizedDeckIds: [deckId],
      );
      await outcomes.markCapabilityTerminal(speciesId, EnrichmentCapability.base, state);
    }

    test('resets a done row unconditionally, without any reference-DB '
        'version comparison', () async {
      await seedBaseTerminal('sp-a', 'deck-1', state: EnrichmentWorkState.done);
      await database.update(
        EnrichmentWorkTables.capabilityState,
        {
          'reference_db_version': 99,
          'attempt_count': 3,
          'last_error': 'stale error',
        },
        where: "species_id = 'sp-a' AND capability = 'base'",
      );

      final resetCount = await maintenance.resetBaseCapabilityForRetrigger(
        'deck-1',
      );
      expect(resetCount, 1);

      final row = (await database.query(
        EnrichmentWorkTables.capabilityState,
        where: "species_id = 'sp-a' AND capability = 'base'",
      )).single;
      expect(row['state'], 'pending');
      expect(row['attempt_count'], 0);
      expect(row['last_error'], isNull);
    });

    test('resets a noResult row too', () async {
      await seedBaseTerminal('sp-a', 'deck-1', state: EnrichmentWorkState.noResult);

      final resetCount = await maintenance.resetBaseCapabilityForRetrigger(
        'deck-1',
      );
      expect(resetCount, 1);
    });

    test('resets a permanentFailure row too — unlike resetStaleBaseCapability, '
        'a manual retrigger should retry those as well', () async {
      await seedBaseTerminal('sp-a', 'deck-1', state: EnrichmentWorkState.permanentFailure);

      final resetCount = await maintenance.resetBaseCapabilityForRetrigger(
        'deck-1',
      );
      expect(resetCount, 1);

      final row = (await database.query(
        EnrichmentWorkTables.capabilityState,
        where: "species_id = 'sp-a' AND capability = 'base'",
      )).single;
      expect(row['state'], 'pending');
    });

    test('only touches species that are members of the given deck', () async {
      await seedBaseTerminal('sp-a', 'deck-1', state: EnrichmentWorkState.done);
      await seedBaseTerminal('sp-b', 'deck-2', state: EnrichmentWorkState.done);

      final resetCount = await maintenance.resetBaseCapabilityForRetrigger(
        'deck-1',
      );
      expect(resetCount, 1);

      final spB = (await database.query(
        EnrichmentWorkTables.capabilityState,
        where: "species_id = 'sp-b' AND capability = 'base'",
      )).single;
      expect(spB['state'], 'done');
    });

    test('is a harmless no-op for a deck whose species have no base row yet '
        '(never enriched at all)', () async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-1'],
      );
      // sp-a's base row already exists (seeded 'pending' by assignSpeciesOwners
      // itself), but nothing terminal yet — nothing for this call to touch.
      final resetCount = await maintenance.resetBaseCapabilityForRetrigger(
        'deck-1',
      );
      expect(resetCount, 0);
    });
  });

  test('clearRetryAttemptForRetryScheduledWorkItems clears next_attempt_at '
      'across all three queue tables', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final future = now + 60000;
    await database.insert(EnrichmentWorkTables.capabilityState, {
      'species_id': 'sp-a',
      'capability': 'inatPrimary',
      'state': 'retryScheduled',
      'priority_tier': 10,
      'attempt_count': 1,
      'next_attempt_at': future,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkTables.taxonomyWork, {
      'work_key': 'genus:acropora',
      'runtime_entity_key': 'genus:acropora',
      'common_names_state': 'retryScheduled',
      'attempt_count': 1,
      'next_attempt_at': future,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkTables.unresolvedNames, {
      'deck_id': 'deck-1',
      'name': 'Unknownus fishus',
      'state': 'retryScheduled',
      'attempt_count': 1,
      'next_attempt_at': future,
      'updated_at': now,
    });

    final cleared = await maintenance
        .clearRetryAttemptForRetryScheduledWorkItems();
    expect(cleared, 3);

    final capabilityRows = await database.query(
      EnrichmentWorkTables.capabilityState,
    );
    expect(capabilityRows.single['next_attempt_at'], isNull);
    final taxonomyRows = await database.query(
      EnrichmentWorkTables.taxonomyWork,
    );
    expect(taxonomyRows.single['next_attempt_at'], isNull);
    final unresolvedRows = await database.query(
      EnrichmentWorkTables.unresolvedNames,
    );
    expect(unresolvedRows.single['next_attempt_at'], isNull);
  });

  test('recoverInterruptedWork reverts running rows back to pending across all '
      'three queue tables', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.insert(EnrichmentWorkTables.capabilityState, {
      'species_id': 'sp-a',
      'capability': 'base',
      'state': 'running',
      'priority_tier': 0,
      'attempt_count': 0,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkTables.taxonomyWork, {
      'work_key': 'genus:acropora',
      'runtime_entity_key': 'genus:acropora',
      'common_names_state': 'running',
      'attempt_count': 0,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkTables.unresolvedNames, {
      'deck_id': 'deck-1',
      'name': 'Unknownus fishus',
      'state': 'running',
      'attempt_count': 0,
      'updated_at': now,
    });

    await maintenance.recoverInterruptedWork();

    final capabilityRows = await database.query(
      EnrichmentWorkTables.capabilityState,
    );
    expect(capabilityRows.single['state'], 'pending');
    final taxonomyRows = await database.query(
      EnrichmentWorkTables.taxonomyWork,
    );
    expect(taxonomyRows.single['common_names_state'], 'pending');
    final unresolvedRows = await database.query(
      EnrichmentWorkTables.unresolvedNames,
    );
    expect(unresolvedRows.single['state'], 'pending');
  });

  test(
    'deleteAllNonTerminalWork removes every non-terminal capability/taxonomy/'
    'unresolved-name row (and orphaned taxonomy-species junction rows), '
    'leaving terminal rows and enrichment_species_work untouched',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await database.insert(EnrichmentWorkTables.speciesWork, {
        'species_id': 'sp-a',
        'owner_deck_id': 'deck-1',
        'deck_count': 1,
        'wants_inat_photos': 1,
        'wants_common_names': 1,
        'updated_at': now,
      });
      await database.insert(EnrichmentWorkTables.capabilityState, {
        'species_id': 'sp-a',
        'capability': 'base',
        'state': 'done',
        'priority_tier': 0,
        'attempt_count': 0,
        'updated_at': now,
      });
      await database.insert(EnrichmentWorkTables.capabilityState, {
        'species_id': 'sp-a',
        'capability': 'inatPrimary',
        'state': 'pending',
        'priority_tier': 10,
        'attempt_count': 0,
        'updated_at': now,
      });
      await database.insert(EnrichmentWorkTables.capabilityState, {
        'species_id': 'sp-a',
        'capability': 'inatBackfill',
        'state': 'retryScheduled',
        'priority_tier': 40,
        'attempt_count': 2,
        'updated_at': now,
      });

      await database.insert(EnrichmentWorkTables.taxonomyWork, {
        'work_key': 'genus:acropora',
        'runtime_entity_key': 'genus:acropora',
        'common_names_state': 'done',
        'attempt_count': 0,
        'updated_at': now,
      });
      await database.insert(EnrichmentWorkTables.taxonomyWork, {
        'work_key': 'genus:favia',
        'runtime_entity_key': 'genus:favia',
        'common_names_state': 'pending',
        'attempt_count': 0,
        'updated_at': now,
      });
      await database.insert(
        EnrichmentWorkTables.taxonomyWorkSpecies,
        {'work_key': 'genus:acropora', 'species_id': 'sp-a'},
      );
      await database.insert(
        EnrichmentWorkTables.taxonomyWorkSpecies,
        {'work_key': 'genus:favia', 'species_id': 'sp-a'},
      );

      await database.insert(EnrichmentWorkTables.unresolvedNames, {
        'deck_id': 'deck-1',
        'name': 'Resolved species',
        'state': 'permanentFailure',
        'attempt_count': 5,
        'updated_at': now,
      });
      await database.insert(EnrichmentWorkTables.unresolvedNames, {
        'deck_id': 'deck-1',
        'name': 'Still trying species',
        'state': 'retryScheduled',
        'attempt_count': 1,
        'updated_at': now,
      });

      final removed = await maintenance.deleteAllNonTerminalWork();

      // inatPrimary + inatBackfill + genus:favia + "Still trying species"
      expect(removed, 4);

      final capabilityRows = await database.query(
        EnrichmentWorkTables.capabilityState,
        orderBy: 'capability',
      );
      expect(capabilityRows.map((r) => r['capability']), ['base']);

      final taxonomyRows = await database.query(
        EnrichmentWorkTables.taxonomyWork,
      );
      expect(taxonomyRows.map((r) => r['work_key']), ['genus:acropora']);
      final taxonomySpeciesRows = await database.query(
        EnrichmentWorkTables.taxonomyWorkSpecies,
      );
      expect(taxonomySpeciesRows.map((r) => r['work_key']), ['genus:acropora']);

      final unresolvedRows = await database.query(
        EnrichmentWorkTables.unresolvedNames,
      );
      expect(unresolvedRows.map((r) => r['name']), ['Resolved species']);

      // enrichment_species_work (ownership/consent) is left untouched.
      final speciesWorkRows = await database.query(
        EnrichmentWorkTables.speciesWork,
      );
      expect(speciesWorkRows, hasLength(1));
    },
  );
}
