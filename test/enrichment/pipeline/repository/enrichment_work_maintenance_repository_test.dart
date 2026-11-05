import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/base_image_retry_policy.dart';
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

    group('a permanentFailure row', () {
      Future<void> seedGivenUp({int? referenceDbVersion}) async {
        await seedBaseTerminal(
          'sp-a',
          'deck-1',
          state: EnrichmentWorkState.done,
        );
        await database.update(
          EnrichmentWorkTables.capabilityState,
          {
            'state': 'permanentFailure',
            'attempt_count': 5,
            'reference_db_version': referenceDbVersion,
          },
          where: "species_id = 'sp-a' AND capability = 'base'",
        );
      }

      test('stamped with an older version is stale and reset', () async {
        await seedGivenUp(referenceDbVersion: 5);

        expect(
          await maintenance.countStaleBaseSpecies(
            deckId: 'deck-1',
            currentReferenceDbVersion: 6,
          ),
          1,
        );
        expect(
          await maintenance.resetStaleBaseCapability(
            deckId: 'deck-1',
            currentReferenceDbVersion: 6,
          ),
          1,
        );
        final row = (await database.query(
          EnrichmentWorkTables.capabilityState,
          where: "species_id = 'sp-a' AND capability = 'base'",
        )).single;
        expect(row['state'], 'pending');
        expect(row['attempt_count'], 0);
      });

      test('never stamped is stale and reset', () async {
        await seedGivenUp();

        expect(
          await maintenance.countStaleBaseSpecies(
            deckId: 'deck-1',
            currentReferenceDbVersion: 6,
          ),
          1,
        );
        expect(
          await maintenance.resetStaleBaseCapability(
            deckId: 'deck-1',
            currentReferenceDbVersion: 6,
          ),
          1,
        );
      });

      test('stamped with the current version is left alone', () async {
        await seedGivenUp(referenceDbVersion: 6);

        expect(
          await maintenance.countStaleBaseSpecies(
            deckId: 'deck-1',
            currentReferenceDbVersion: 6,
          ),
          0,
        );
        expect(
          await maintenance.resetStaleBaseCapability(
            deckId: 'deck-1',
            currentReferenceDbVersion: 6,
          ),
          0,
        );
      });
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

    test('resets a permanentFailure row too, whatever its stamp — a manual '
        'retrigger should retry those as well', () async {
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

    test('resets a row waiting out its long phase, keeping its fallback '
        'marking, and leaves one in its short phase alone', () async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-short', 'sp-long'},
        },
        prioritizedDeckIds: ['deck-1'],
      );
      final tomorrow = DateTime.now()
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch;
      const marking = {
        'fallback_reason': 'hostUnavailable',
        'fallback_host': 'www.fishbase.se',
        'fallback_at': 1700,
      };
      Future<void> scheduleRetry(
        String speciesId,
        int attemptCount, {
        Map<String, Object?> extra = const {},
      }) => database.update(
        EnrichmentWorkTables.capabilityState,
        {
          ...extra,
          'state': 'retryScheduled',
          'attempt_count': attemptCount,
          'next_attempt_at': tomorrow,
        },
        where: "species_id = ? AND capability = 'base'",
        whereArgs: [speciesId],
      );
      await scheduleRetry(
        'sp-short',
        BaseImageRetryPolicy.shortPhaseAttempts - 1,
      );
      await scheduleRetry(
        'sp-long',
        BaseImageRetryPolicy.shortPhaseAttempts,
        extra: marking,
      );

      final resetCount = await maintenance.resetBaseCapabilityForRetrigger(
        'deck-1',
      );

      expect(resetCount, 1);
      final rows = {
        for (final row in await database.query(
          EnrichmentWorkTables.capabilityState,
          where: "capability = 'base'",
        ))
          row['species_id']: row,
      };
      expect(
        rows['sp-long'],
        _has({
          ...marking,
          'state': 'pending',
          'attempt_count': 0,
          'next_attempt_at': null,
        }),
      );
      expect(
        rows['sp-short'],
        _has({
          'state': 'retryScheduled',
          'attempt_count': BaseImageRetryPolicy.shortPhaseAttempts - 1,
          'next_attempt_at': tomorrow,
        }),
      );
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

  test('clearRetryAttemptForRetryScheduledWorkItems leaves a base row in its '
      'long phase waiting, and brings a short-phase one forward', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final tomorrow = now + const Duration(days: 1).inMilliseconds;
    Future<void> insertBase(String speciesId, int attemptCount) =>
        database.insert(EnrichmentWorkTables.capabilityState, {
          'species_id': speciesId,
          'capability': 'base',
          'state': 'retryScheduled',
          'priority_tier': 0,
          'attempt_count': attemptCount,
          'next_attempt_at': tomorrow,
          'updated_at': now,
        });
    await insertBase('sp-short', BaseImageRetryPolicy.shortPhaseAttempts - 1);
    await insertBase('sp-long', BaseImageRetryPolicy.shortPhaseAttempts);

    final cleared = await maintenance
        .clearRetryAttemptForRetryScheduledWorkItems();

    expect(cleared, 1);
    final nextAttemptBySpecies = {
      for (final row in await database.query(
        EnrichmentWorkTables.capabilityState,
      ))
        row['species_id']: row['next_attempt_at'],
    };
    expect(nextAttemptBySpecies['sp-short'], isNull);
    expect(nextAttemptBySpecies['sp-long'], tomorrow);
  });

  test('the fallback marking survives every reset', () async {
    await repository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-1': {'sp-a'},
      },
      prioritizedDeckIds: ['deck-1'],
    );
    const marking = {
      'fallback_reason': 'hostUnavailable',
      'fallback_host': 'www.fishbase.se',
      'fallback_at': 1700,
    };
    Future<Map<String, Object?>> baseRow() async => (await database.query(
      EnrichmentWorkTables.capabilityState,
      where: "species_id = 'sp-a' AND capability = 'base'",
    )).single;
    Future<void> markGivenUp() => database.update(
      EnrichmentWorkTables.capabilityState,
      {...marking, 'state': 'permanentFailure', 'next_attempt_at': 1},
      where: "species_id = 'sp-a' AND capability = 'base'",
    );

    await markGivenUp();
    await maintenance.resetStaleBaseCapability(currentReferenceDbVersion: 6);
    expect(await baseRow(), _has({...marking, 'state': 'pending'}));

    await markGivenUp();
    await maintenance.resetBaseCapabilityForRetrigger('deck-1');
    expect(await baseRow(), _has({...marking, 'state': 'pending'}));

    await database.update(
      EnrichmentWorkTables.capabilityState,
      {'state': 'retryScheduled', 'attempt_count': 1, 'next_attempt_at': 1},
      where: "species_id = 'sp-a' AND capability = 'base'",
    );
    await maintenance.clearRetryAttemptForRetryScheduledWorkItems();
    expect(await baseRow(), _has({...marking, 'next_attempt_at': null}));
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

/// Matches a row holding every entry of [entries].
Matcher _has(Map<String, Object?> entries) => allOf([
  for (final MapEntry(:key, :value) in entries.entries)
    containsPair(key, value),
]);
