import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/pipeline/repository/deck_enrichment_projection_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_outcome_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

/// Covers the queries themselves — that the joins reach the right rows.
/// What is then *derived* from those rows is tested against
/// `DeckProjectionBuilder` directly, without a database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentOwnershipRepository repository;
  late EnrichmentWorkOutcomeRepository outcomes;
  late DeckEnrichmentProjectionRepository projections;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    repository = EnrichmentOwnershipRepository(database);
    outcomes = EnrichmentWorkOutcomeRepository(database);
    projections = DeckEnrichmentProjectionRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

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
      await outcomes.markCapabilityTerminal(
        'sp-a',
        EnrichmentCapability.base,
        EnrichmentWorkState.done,
      );

      // sp-b: base noResult, inatPrimary done -> complete, has image.
      await outcomes.markCapabilityTerminal(
        'sp-b',
        EnrichmentCapability.base,
        EnrichmentWorkState.noResult,
      );
      await outcomes.seedCapability(
        'sp-b',
        EnrichmentCapability.inatPrimary,
        priorityTier: 10,
      );
      await outcomes.markCapabilityTerminal(
        'sp-b',
        EnrichmentCapability.inatPrimary,
        EnrichmentWorkState.done,
      );

      // sp-c: owned by deck-2 for cross-deck dedup, but also referenced by
      // deck-1 via membership -> must still be included in deck-1's
      // projection regardless of ownership.
      await outcomes.markCapabilityTerminal(
        'sp-c',
        EnrichmentCapability.base,
        EnrichmentWorkState.done,
      );

      final projection = await projections.loadDeckProjection('deck-1');

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
        await outcomes.markCapabilityTerminal(
          'sp-a',
          EnrichmentCapability.base,
          EnrichmentWorkState.noResult,
        );
        await outcomes.seedCapability(
          'sp-a',
          EnrichmentCapability.inatPrimary,
          priorityTier: 10,
        );

        final projection = await projections.loadDeckProjection('deck-1');

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
      await outcomes.markCapabilityTerminal(
        'sp-a',
        EnrichmentCapability.base,
        EnrichmentWorkState.noResult,
      );
      await outcomes.seedCapability(
        'sp-a',
        EnrichmentCapability.inatPrimary,
        priorityTier: 10,
      );
      await outcomes.markCapabilityTerminal(
        'sp-a',
        EnrichmentCapability.inatPrimary,
        EnrichmentWorkState.noResult,
      );

      final projection = await projections.loadDeckProjection('deck-1');

      expect(projection.imageStagesComplete, isTrue);
      expect(projection.hasAnyImage, isFalse);
    });

    test(
      'a species without iNat-photo consent whose base has no image is '
      'still counted as image-complete, so the deck is not stuck waiting on '
      'an inatPrimary request that will never be made',
      () async {
        await repository.assignSpeciesOwners(
          speciesIdsByDeckId: {
            'deck-1': {'sp-a'},
          },
          prioritizedDeckIds: ['deck-1'],
          includeInatPhotosByDeckId: {'deck-1': false},
        );
        await outcomes.markCapabilityTerminal(
          'sp-a',
          EnrichmentCapability.base,
          EnrichmentWorkState.noResult,
        );
        // No inatPrimary row: seedCapability no-ops without consent, exactly
        // as BaseWorker's reactive fallback would.
        await outcomes.seedCapability(
          'sp-a',
          EnrichmentCapability.inatPrimary,
          priorityTier: 10,
        );

        final projection = await projections.loadDeckProjection('deck-1');

        expect(projection.imageStagesComplete, isTrue);
        expect(projection.hasAnyImage, isFalse);
      },
    );

    test('counts species-common-names and backfill only for species that '
        'actually have those capabilities seeded', () async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a', 'sp-b'},
        },
        prioritizedDeckIds: ['deck-1'],
        includeCommonNamesByDeckId: {'deck-1': true},
      );
      await outcomes.markCapabilityTerminal(
        'sp-a',
        EnrichmentCapability.speciesCommonNames,
        EnrichmentWorkState.done,
      );
      // sp-b's speciesCommonNames stays pending.
      await outcomes.seedCapability(
        'sp-a',
        EnrichmentCapability.inatBackfill,
        priorityTier: 40,
      );
      await outcomes.markCapabilityTerminal(
        'sp-a',
        EnrichmentCapability.inatBackfill,
        EnrichmentWorkState.done,
      );

      final projection = await projections.loadDeckProjection('deck-1');

      expect(projection.speciesCommonNamesWantedCount, 2);
      expect(projection.speciesCommonNamesTerminalCount, 1);
      expect(projection.inatBackfillWantedCount, 1);
      expect(projection.inatBackfillTerminalCount, 1);
    });

    test(
      'counts taxonomy items relevant to the deck via species membership, and '
      'surfaces permanent failures from either species or taxonomy work',
      () async {
        await repository.assignSpeciesOwners(
          speciesIdsByDeckId: {
            'deck-1': {'sp-a'},
          },
          prioritizedDeckIds: ['deck-1'],
        );
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
        await outcomes.markTaxonomyCapabilityTerminal(
          'genus:acropora',
          EnrichmentWorkState.done,
        );
        // Unrelated taxon whose species is not a member of deck-1 — the
        // derived deck scoping (species junction ⋈ membership) must exclude it.
        await repository.registerTaxonomyWork(
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

        var projection = await projections.loadDeckProjection('deck-1');
        expect(projection.taxonomyTotalCount, 1);
        expect(projection.taxonomyTerminalCount, 1);
        expect(projection.anyPermanentFailure, isFalse);

        await outcomes.recordCapabilityAttemptFailure(
          'sp-a',
          EnrichmentCapability.base,
          maxAttempts: 1,
          backoffSteps: const [Duration(seconds: 1)],
        );
        projection = await projections.loadDeckProjection('deck-1');
        expect(projection.anyPermanentFailure, isTrue);
      },
    );

    test(
      'a deck with no tracked species returns an empty-shaped projection',
      () async {
        final projection = await projections.loadDeckProjection('deck-none');

        expect(projection.speciesCount, 0);
        expect(projection.imageStagesComplete, isFalse);
        expect(projection.hasAnyImage, isFalse);
      },
    );

    test('staleBaseSpeciesCount is 0 when currentReferenceDbVersion is '
        'omitted, regardless of stored versions', () async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-1'],
      );
      await outcomes.markCapabilityTerminal(
        'sp-a',
        EnrichmentCapability.base,
        EnrichmentWorkState.done,
        referenceDbVersion: 1,
      );

      final projection = await projections.loadDeckProjection('deck-1');
      expect(projection.staleBaseSpeciesCount, 0);
      expect(projection.hasStaleBaseImages, isFalse);
    });

    test('counts a done species with an older stamped version as stale, and '
        'a matching/newer version as not stale', () async {
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
        referenceDbVersion: 1,
      );
      await outcomes.markCapabilityTerminal(
        'sp-b',
        EnrichmentCapability.base,
        EnrichmentWorkState.done,
        referenceDbVersion: 6,
      );

      final projection = await projections.loadDeckProjection(
        'deck-1',
        currentReferenceDbVersion: 6,
      );
      expect(projection.staleBaseSpeciesCount, 1);
      expect(projection.hasStaleBaseImages, isTrue);
    });

    test('counts a noResult species the same way', () async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-1'],
      );
      await outcomes.markCapabilityTerminal(
        'sp-a',
        EnrichmentCapability.base,
        EnrichmentWorkState.noResult,
        referenceDbVersion: 1,
      );

      final projection = await projections.loadDeckProjection(
        'deck-1',
        currentReferenceDbVersion: 6,
      );
      expect(projection.staleBaseSpeciesCount, 1);
    });

    test('a species whose base capability is not yet terminal is never '
        'counted as stale', () async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-1'],
      );

      final projection = await projections.loadDeckProjection(
        'deck-1',
        currentReferenceDbVersion: 6,
      );
      expect(projection.staleBaseSpeciesCount, 0);
    });
  });

  group('loadDeckIdsUpdatedSince', () {
    test('returns decks with changes across capability, taxonomy, and '
        'unresolved-name tables (taxonomy scoped via species membership)',
        () async {
      final threshold = DateTime.now().millisecondsSinceEpoch;
      final after = threshold + 1000;

      // deck-1 changes via a capability row, reached through sp-a's membership.
      await database.insert(EnrichmentWorkTables.deckMembership, {
        'species_id': 'sp-a',
        'deck_id': 'deck-1',
      });
      await database.insert(EnrichmentWorkTables.capabilityState, {
        'species_id': 'sp-a',
        'capability': 'base',
        'state': 'pending',
        'priority_tier': 0,
        'attempt_count': 0,
        'updated_at': after,
      });

      // deck-2 changes via a taxonomy row, reached through sp-b's membership
      // and the species junction — with no capability row of its own.
      await database.insert(EnrichmentWorkTables.deckMembership, {
        'species_id': 'sp-b',
        'deck_id': 'deck-2',
      });
      await database.insert(EnrichmentWorkTables.taxonomyWork, {
        'work_key': 'genus:acropora',
        'runtime_entity_key': 'genus:acropora',
        'common_names_state': 'pending',
        'attempt_count': 0,
        'updated_at': after,
      });
      await database.insert(EnrichmentWorkTables.taxonomyWorkSpecies, {
        'work_key': 'genus:acropora',
        'species_id': 'sp-b',
      });

      // deck-3 changes via an unresolved name.
      await database.insert(EnrichmentWorkTables.unresolvedNames, {
        'deck_id': 'deck-3',
        'name': 'Unknownus fishus',
        'state': 'pending',
        'wants_inat_photos': 1,
        'wants_common_names': 1,
        'attempt_count': 0,
        'updated_at': after,
      });

      final changedDeckIds = await projections.loadDeckIdsUpdatedSince(
        threshold - 1,
      );
      expect(changedDeckIds, {'deck-1', 'deck-2', 'deck-3'});

      expect(await projections.loadDeckIdsUpdatedSince(after + 10000), isEmpty);
    });
  });

  group('diagnostics state counts', () {
    test('loadCapabilityStateCounts groups by capability and state', () async {
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
      );

      final counts = await projections.loadCapabilityStateCounts();

      final baseCounts = {
        for (final entry in counts.where((entry) => entry.label == 'base'))
          entry.state: entry.count,
      };
      expect(baseCounts[EnrichmentWorkState.pending], 1);
      expect(baseCounts[EnrichmentWorkState.done], 1);
    });

    test(
      'loadCapabilityStateCounts surfaces the next scheduled retry time',
      () async {
        await repository.assignSpeciesOwners(
          speciesIdsByDeckId: {
            'deck-1': {'sp-a'},
          },
          prioritizedDeckIds: ['deck-1'],
        );
        await outcomes.recordCapabilityAttemptFailure(
          'sp-a',
          EnrichmentCapability.base,
          maxAttempts: 5,
          backoffSteps: const [Duration(seconds: 15)],
          error: 'timeout',
          failureKind: 'temporary',
        );

        final counts = await projections.loadCapabilityStateCounts();
        final retryEntry = counts.firstWhere(
          (entry) => entry.label == 'base' && entry.state == EnrichmentWorkState.retryScheduled,
        );

        expect(retryEntry.nextAttemptAt, isNotNull);
        expect(
          retryEntry.nextAttemptAt!.isAfter(DateTime.now()),
          isTrue,
        );
      },
    );

    test('loadTaxonomyWorkStateCounts groups by common_names_state', () async {
      await repository.registerTaxonomyWork(
        items: [
          const TaxonomyWorkPlanItem(
            workKey: 'genus:taxon:1',
            runtimeEntityKey: 'genus:gobius',
            rank: 'genus',
            scientificName: 'Gobius',
            speciesIds: {'sp-a'},
          ),
        ],
      );

      final counts = await projections.loadTaxonomyWorkStateCounts();

      expect(counts, hasLength(1));
      expect(counts.single.label, 'taxonomyCommonNames');
      expect(counts.single.state, EnrichmentWorkState.pending);
      expect(counts.single.count, 1);
    });

    test('loadUnresolvedNamesStateCounts groups by state', () async {
      await database.insert(EnrichmentWorkTables.unresolvedNames, {
        'deck_id': 'deck-1',
        'name': 'Ghostus fishus',
        'state': 'permanentFailure',
        'wants_inat_photos': 1,
        'wants_common_names': 1,
        'attempt_count': 5,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      final counts = await projections.loadUnresolvedNamesStateCounts();

      expect(counts, hasLength(1));
      expect(counts.single.label, 'unresolvedNames');
      expect(counts.single.state, EnrichmentWorkState.permanentFailure);
      expect(counts.single.count, 1);
    });
  });

  group('getPendingCommonNameSpeciesIds', () {
    test(
      'returns only species whose speciesCommonNames capability is not '
      'yet terminal, ignoring species that never consented to it',
      () async {
        await repository.assignSpeciesOwners(
          speciesIdsByDeckId: {
            'deck-1': {'sp-pending', 'sp-done', 'sp-no-consent'},
          },
          prioritizedDeckIds: ['deck-1'],
          includeCommonNamesByDeckId: {'deck-1': true},
        );
        // sp-no-consent was seeded above with consent=true (deck-level), so
        // re-register it without common-name consent to simulate a species
        // that never wanted this capability in the first place.
        await database.delete(
          EnrichmentWorkTables.capabilityState,
          where: 'species_id = ? AND capability = ?',
          whereArgs: ['sp-no-consent', 'speciesCommonNames'],
        );

        await outcomes.markCapabilityTerminal(
          'sp-done',
          EnrichmentCapability.speciesCommonNames,
          EnrichmentWorkState.done,
        );

        final pending = await projections.getPendingCommonNameSpeciesIds({
          'sp-pending',
          'sp-done',
          'sp-no-consent',
        });

        expect(pending, {'sp-pending'});
      },
    );

    test('returns an empty set for an empty input', () async {
      final pending = await projections.getPendingCommonNameSpeciesIds({});
      expect(pending, isEmpty);
    });
  });
}
