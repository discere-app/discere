import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/pipeline/repository/deck_enrichment_projection_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_claim_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_outcome_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

/// Ownership and consent as they land in the database. The rules being
/// applied are tested against `SpeciesOwnershipPlanner` directly, without
/// one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentOwnershipRepository repository;
  late EnrichmentWorkOutcomeRepository outcomes;
  late DeckEnrichmentProjectionRepository projections;
  late EnrichmentWorkClaimRepository claims;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    repository = EnrichmentOwnershipRepository(database);
    outcomes = EnrichmentWorkOutcomeRepository(database);
    projections = DeckEnrichmentProjectionRepository(database);
    claims = EnrichmentWorkClaimRepository(database);
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

  test('registerTaxonomyWork merges repeat calls for the same taxon into a '
      'single row, unioning species membership in the junction', () async {
    await repository.registerTaxonomyWork(
      items: [
        const TaxonomyWorkPlanItem(
          workKey: 'genus:taxon:1',
          runtimeEntityKey: 'genus:acropora',
          rank: 'genus',
          scientificName: 'Acropora',
          speciesIds: {'sp-a', 'sp-b'},
        ),
      ],
    );
    await repository.registerTaxonomyWork(
      items: [
        const TaxonomyWorkPlanItem(
          workKey: 'genus:taxon:1',
          runtimeEntityKey: 'genus:acropora',
          rank: 'genus',
          scientificName: 'Acropora',
          speciesIds: {'sp-c'},
        ),
      ],
    );

    final rows = await database.query(
      EnrichmentWorkTables.taxonomyWork,
      where: 'runtime_entity_key = ?',
      whereArgs: ['genus:acropora'],
    );
    expect(rows, hasLength(1));

    final speciesRows = await database.query(
      EnrichmentWorkTables.taxonomyWorkSpecies,
      where: 'work_key = ?',
      whereArgs: ['genus:taxon:1'],
      orderBy: 'species_id ASC',
    );
    expect(speciesRows.map((r) => r['species_id']), ['sp-a', 'sp-b', 'sp-c']);
  });

  test(
    'releaseDeck removes the deck membership and reassigns shared-species '
    'ownership, leaving shared taxonomy work as permanent cache',
    () async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a', 'sp-b'},
          'deck-2': {'sp-b'},
        },
        prioritizedDeckIds: ['deck-1', 'deck-2'],
      );

      await repository.registerTaxonomyWork(
        items: [
          const TaxonomyWorkPlanItem(
            workKey: 'genus:taxon:1',
            runtimeEntityKey: 'genus:acropora',
            rank: 'genus',
            scientificName: 'Acropora',
            speciesIds: {'sp-a', 'sp-b'},
          ),
        ],
      );

      await repository.releaseDeck('deck-2');

      final speciesRows = await database.query(
        EnrichmentWorkTables.speciesWork,
        where: 'species_id = ?',
        whereArgs: ['sp-b'],
      );
      expect(speciesRows, hasLength(1));
      expect(speciesRows.single['deck_count'], 1);

      final membershipRows = await database.query(
        EnrichmentWorkTables.deckMembership,
        where: 'species_id = ?',
        whereArgs: ['sp-b'],
      );
      expect(membershipRows.map((row) => row['deck_id']), ['deck-1']);

      // Taxonomy work carries no deck association and is shared dedup cache —
      // releaseDeck never touches it.
      final taxonomyRows = await database.query(
        EnrichmentWorkTables.taxonomyWork,
        where: 'runtime_entity_key = ?',
        whereArgs: ['genus:acropora'],
      );
      expect(taxonomyRows, hasLength(1));
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
      EnrichmentWorkTables.speciesWork,
      where: 'species_id = ?',
      whereArgs: ['sp-shared'],
    );
    expect(rows.single['wants_inat_photos'], 1);
    expect(rows.single['wants_common_names'], 0);

    // base is always seeded; speciesCommonNames is not, since consent for
    // it never flipped true across either call.
    final capabilityRows = await database.query(
      EnrichmentWorkTables.capabilityState,
      where: 'species_id = ?',
      whereArgs: ['sp-shared'],
    );
    expect(capabilityRows.map((r) => r['capability']), ['base']);

    final membershipRows = await database.query(
      EnrichmentWorkTables.deckMembership,
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
      EnrichmentWorkTables.speciesWork,
      where: 'species_id = ?',
      whereArgs: ['sp-shared'],
    );
    expect(rows.single['wants_common_names'], 1);

    final capabilityRows = await database.query(
      EnrichmentWorkTables.capabilityState,
      where: 'species_id = ? AND capability = ?',
      whereArgs: ['sp-shared', 'speciesCommonNames'],
    );
    expect(capabilityRows, hasLength(1));
  });

  test(
    'assignSpeciesOwners retroactively seeds inatPrimary/inatBackfill when '
    'consent arrives after base already resolved without an image — the '
    'import flow schedules once without consent to start base downloads '
    'immediately, then again with the real consent once the user has seen '
    'the import dialog',
    () async {
      // First call (mirrors the import flow's immediate, consent-withheld
      // schedule): base resolves noResult before consent is known, so the
      // reactive BaseWorker fallback would no-op.
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
      await outcomes.seedCapability(
        'sp-a',
        EnrichmentCapability.inatPrimary,
        priorityTier: 10,
      );
      var inatPrimaryRows = await database.query(
        EnrichmentWorkTables.capabilityState,
        where: 'species_id = ? AND capability = ?',
        whereArgs: ['sp-a', 'inatPrimary'],
      );
      expect(inatPrimaryRows, isEmpty);

      // Second call (the user confirmed the import dialog): consent arrives
      // after base is already terminal.
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-1'],
        includeInatPhotosByDeckId: {'deck-1': true},
      );

      inatPrimaryRows = await database.query(
        EnrichmentWorkTables.capabilityState,
        where: 'species_id = ? AND capability = ?',
        whereArgs: ['sp-a', 'inatPrimary'],
      );
      expect(inatPrimaryRows, hasLength(1));
      expect(inatPrimaryRows.single['state'], 'pending');

      final inatBackfillRows = await database.query(
        EnrichmentWorkTables.capabilityState,
        where: 'species_id = ? AND capability = ?',
        whereArgs: ['sp-a', 'inatBackfill'],
      );
      expect(inatBackfillRows, hasLength(1));
      expect(inatBackfillRows.single['state'], 'pending');
    },
  );

  test(
    'assignSpeciesOwners retroactively seeds only inatBackfill (not '
    'inatPrimary) when consent arrives after base already succeeded — '
    'the species already has a reference image, so iNat only ever '
    'supplements it, exactly like BaseWorker\'s own success-path seed',
    () async {
      // First call (mirrors "Nur Basisdaten" on import): base succeeds
      // before iNat consent is known.
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
        EnrichmentWorkState.done,
      );

      // Second call (the user later clicks "Erneut anreichern" / "Jetzt
      // anreichern" and picks "Vollständig"): consent arrives after base
      // already succeeded.
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-1'],
        includeInatPhotosByDeckId: {'deck-1': true},
      );

      final inatPrimaryRows = await database.query(
        EnrichmentWorkTables.capabilityState,
        where: 'species_id = ? AND capability = ?',
        whereArgs: ['sp-a', 'inatPrimary'],
      );
      expect(
        inatPrimaryRows,
        isEmpty,
        reason:
            'inatPrimary is only for species with no reference image at '
            'all — a species whose base already succeeded must never get '
            'one, matching BaseWorker never seeding it on its own success '
            'path either',
      );

      final inatBackfillRows = await database.query(
        EnrichmentWorkTables.capabilityState,
        where: 'species_id = ? AND capability = ?',
        whereArgs: ['sp-a', 'inatBackfill'],
      );
      expect(inatBackfillRows, hasLength(1));
      expect(inatBackfillRows.single['state'], 'pending');
    },
  );

  test(
    'a fully-terminal species keeps its membership and capability-state rows '
    'so the deck stays computable as done',
    () async {
      await repository.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-1': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-1'],
        includeCommonNamesByDeckId: {'deck-1': false},
      );
      await outcomes.markCapabilityTerminal(
        'sp-a',
        EnrichmentCapability.base,
        EnrichmentWorkState.done,
      );

      // Completing a species must not delete its membership row — that row is
      // the deck's species list and the denominator DeckEnrichmentProjection
      // counts to decide "done". It is only removed at deck/species lifecycle
      // events (assignSpeciesOwners drop-loop, releaseDeck).
      final membershipRows = await database.query(
        EnrichmentWorkTables.deckMembership,
        where: 'species_id = ?',
        whereArgs: ['sp-a'],
      );
      expect(membershipRows, hasLength(1));

      final projection = await projections.loadDeckProjection('deck-1');
      expect(projection.speciesCount, 1);
      expect(projection.imageStagesComplete, isTrue);
      expect(projection.allSpeciesWorkTerminal, isTrue);
    },
  );

  Future<Map<String, Map<String, Object?>>> unresolvedRowsByName() async {
    final rows = await database.query(EnrichmentWorkTables.unresolvedNames);
    return {for (final row in rows) '${row['deck_id']}/${row['name']}': row};
  }

  test('mergeUnresolvedNames grants consent to every unresolved name the deck '
      'still has, not only the names it is passed', () async {
    await repository.mergeUnresolvedNames(
      'deck-1',
      ['Name one', 'Name two'],
      wantsInatPhotos: false,
      wantsCommonNames: false,
    );
    await repository.mergeUnresolvedNames(
      'deck-1',
      ['Name three'],
      wantsInatPhotos: false,
      wantsCommonNames: false,
    );

    await repository.mergeUnresolvedNames(
      'deck-1',
      const [],
      wantsInatPhotos: true,
      wantsCommonNames: true,
    );

    final rows = await unresolvedRowsByName();
    expect(rows.keys, {
      'deck-1/Name one',
      'deck-1/Name two',
      'deck-1/Name three',
    });
    for (final row in rows.values) {
      expect(row['wants_inat_photos'], 1, reason: '${row['name']}');
      expect(row['wants_common_names'], 1, reason: '${row['name']}');
    }
  });

  test('mergeUnresolvedNames leaves the unresolved names of other decks '
      'alone', () async {
    await repository.mergeUnresolvedNames(
      'deck-other',
      ['Shared name'],
      wantsInatPhotos: false,
      wantsCommonNames: false,
    );

    await repository.mergeUnresolvedNames(
      'deck-1',
      ['Shared name'],
      wantsInatPhotos: true,
      wantsCommonNames: true,
    );

    final rows = await unresolvedRowsByName();
    expect(rows['deck-other/Shared name']!['wants_inat_photos'], 0);
    expect(rows['deck-other/Shared name']!['wants_common_names'], 0);
    expect(rows['deck-1/Shared name']!['wants_inat_photos'], 1);
  });

  test('mergeUnresolvedNames does not bring back a name that has resolved '
      'since', () async {
    await repository.mergeUnresolvedNames(
      'deck-1',
      ['Resolved name', 'Open name'],
      wantsInatPhotos: false,
      wantsCommonNames: false,
    );
    await outcomes.deleteUnresolvedName('deck-1', 'Resolved name');

    await repository.mergeUnresolvedNames(
      'deck-1',
      const [],
      wantsInatPhotos: true,
      wantsCommonNames: true,
    );

    expect((await unresolvedRowsByName()).keys, {'deck-1/Open name'});
  });

  test('mergeUnresolvedNames never withdraws consent', () async {
    await repository.mergeUnresolvedNames(
      'deck-1',
      ['Name one'],
      wantsInatPhotos: true,
      wantsCommonNames: true,
    );

    await repository.mergeUnresolvedNames(
      'deck-1',
      ['Name one', 'Name two'],
      wantsInatPhotos: false,
      wantsCommonNames: false,
    );

    final rows = await unresolvedRowsByName();
    expect(rows['deck-1/Name one']!['wants_inat_photos'], 1);
    expect(rows['deck-1/Name one']!['wants_common_names'], 1);
    expect(rows['deck-1/Name two']!['wants_inat_photos'], 0);
    expect(rows['deck-1/Name two']!['wants_common_names'], 0);
  });

  test('mergeUnresolvedNames keeps a deck\'s names in line when it grants no '
      'new consent', () async {
    await database.insert(EnrichmentWorkTables.unresolvedNames, {
      'deck_id': 'deck-a',
      'name': 'Older name',
      'state': EnrichmentWorkState.pending.wireName,
      'wants_inat_photos': 0,
      'wants_common_names': 0,
      'attempt_count': 0,
      'updated_at': 1,
    });
    await database.insert(EnrichmentWorkTables.unresolvedNames, {
      'deck_id': 'deck-b',
      'name': 'Newer name',
      'state': EnrichmentWorkState.pending.wireName,
      'wants_inat_photos': 0,
      'wants_common_names': 0,
      'attempt_count': 0,
      'updated_at': 2,
    });

    await repository.mergeUnresolvedNames(
      'deck-a',
      ['Older name'],
      wantsInatPhotos: false,
      wantsCommonNames: false,
    );

    final rows = await unresolvedRowsByName();
    expect(rows['deck-a/Older name']!['updated_at'], 1);
    expect(
      (await claims.claimNextINatWorkItem())!.unresolvedName,
      'Older name',
    );
  });

  test('mergeUnresolvedNames keeps the retry progress of a name it is passed '
      'again', () async {
    await repository.mergeUnresolvedNames(
      'deck-1',
      ['Name one'],
      wantsInatPhotos: false,
      wantsCommonNames: false,
    );
    await database.update(
      EnrichmentWorkTables.unresolvedNames,
      {
        'state': EnrichmentWorkState.retryScheduled.wireName,
        'attempt_count': 2,
        'next_attempt_at': 12345,
        'last_error': 'timeout',
      },
      where: 'deck_id = ? AND name = ?',
      whereArgs: ['deck-1', 'Name one'],
    );

    await repository.mergeUnresolvedNames(
      'deck-1',
      ['Name one'],
      wantsInatPhotos: true,
      wantsCommonNames: true,
    );

    final row = (await unresolvedRowsByName())['deck-1/Name one']!;
    expect(row['state'], EnrichmentWorkState.retryScheduled.wireName);
    expect(row['attempt_count'], 2);
    expect(row['next_attempt_at'], 12345);
    expect(row['last_error'], 'timeout');
    expect(row['wants_inat_photos'], 1);
  });

  test('registerResolvedSpeciesForDeck takes the consent the name row has at '
      'registration, including consent granted after the claim', () async {
    await repository.mergeUnresolvedNames(
      'deck-1',
      ['Name one'],
      wantsInatPhotos: false,
      wantsCommonNames: false,
    );
    final claimed = await claims.claimNextINatWorkItem();
    expect(claimed!.unresolvedName, 'Name one');
    await repository.mergeUnresolvedNames(
      'deck-1',
      const [],
      wantsInatPhotos: true,
      wantsCommonNames: true,
    );

    await repository.registerResolvedSpeciesForDeck(
      'sp-resolved',
      'deck-1',
      resolvedName: 'Name one',
    );

    final row = (await database.query(
      EnrichmentWorkTables.speciesWork,
      where: 'species_id = ?',
      whereArgs: ['sp-resolved'],
    )).single;
    expect(row['wants_inat_photos'], 1);
    expect(row['wants_common_names'], 1);
  });

  test('registerResolvedSpeciesForDeck grants nothing for a name the deck no '
      'longer tracks, and keeps the species\' existing consent', () async {
    await repository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-other': {'sp-resolved'},
      },
      prioritizedDeckIds: ['deck-other'],
      includeInatPhotosByDeckId: {'deck-other': true},
      includeCommonNamesByDeckId: {'deck-other': false},
    );

    await repository.registerResolvedSpeciesForDeck(
      'sp-resolved',
      'deck-1',
      resolvedName: 'Released name',
    );

    final row = (await database.query(
      EnrichmentWorkTables.speciesWork,
      where: 'species_id = ?',
      whereArgs: ['sp-resolved'],
    )).single;
    expect(row['wants_inat_photos'], 1);
    expect(row['wants_common_names'], 0);
  });
}
