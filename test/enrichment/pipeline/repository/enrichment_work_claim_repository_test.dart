import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/inat_work_item.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_claim_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_outcome_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

/// What ends up in the queue and who takes it next.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentOwnershipRepository repository;
  late EnrichmentWorkOutcomeRepository outcomes;
  late EnrichmentWorkClaimRepository claims;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    repository = EnrichmentOwnershipRepository(database);
    outcomes = EnrichmentWorkOutcomeRepository(database);
    claims = EnrichmentWorkClaimRepository(database);
  });

  tearDown(() async {
    await database.close();
  });
  test('claimNextINatWorkItem skips a taxonomy row whose species no longer '
      'have any deck membership, but claims one that still does', () async {
    await database.insert(EnrichmentWorkTables.deckMembership, {
      'species_id': 'sp-live',
      'deck_id': 'deck-1',
    });
    for (final entry in {
      'genus:live': 'sp-live',
      'genus:orphan': 'sp-gone',
    }.entries) {
      await database.insert(EnrichmentWorkTables.taxonomyWork, {
        'work_key': entry.key,
        'runtime_entity_key': entry.key,
        'common_names_state': 'pending',
        'attempt_count': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await database.insert(EnrichmentWorkTables.taxonomyWorkSpecies, {
        'work_key': entry.key,
        'species_id': entry.value,
      });
    }

    final first = await claims.claimNextINatWorkItem();
    expect(first!.kind, INatWorkItemKind.taxonomyCommonNames);
    expect(first.taxonomyWorkKey, 'genus:live');
    expect(first.taxonomySpeciesIds, {'sp-live'});

    // The orphaned taxon (sp-gone has no membership) is never claimed.
    expect(await claims.claimNextINatWorkItem(), isNull);
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
    await claims.seedCapability(
      'sp-a',
      EnrichmentCapability.inatPrimary,
      priorityTier: 10,
    );
    await outcomes.markCapabilityTerminal(
      'sp-a',
      EnrichmentCapability.inatPrimary,
      EnrichmentWorkState.done,
    );

    await claims.seedCapability(
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

  test('claimBaseWorkBatch claims pending species up to the limit and flips '
      'them to running so a later claim only sees what is left', () async {
    await repository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-1': {'sp-a', 'sp-b', 'sp-c'},
      },
      prioritizedDeckIds: ['deck-1'],
    );

    final claimed = await claims.claimBaseWorkBatch(limit: 2);
    expect(claimed, hasLength(2));

    final runningRows = await database.query(
      EnrichmentWorkTables.capabilityState,
      where: "capability = 'base' AND state = 'running'",
    );
    expect(runningRows, hasLength(2));

    final secondClaim = await claims.claimBaseWorkBatch(limit: 5);
    expect(secondClaim, hasLength(1));
  });

  test('claimNextINatWorkItem drains the shared queue in priority order across '
      'species/taxonomy/unresolved-name sources', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Species-scoped claims require an existing EnrichmentWorkTables.deckMembership row (see
    // claimNextINatWorkItem's doc comment) — grant it directly since this
    // test otherwise only cares about raw capability-row priority ordering.
    await database.insert(EnrichmentWorkTables.deckMembership, {
      'species_id': 'sp-a',
      'deck_id': 'deck-1',
    });
    await database.insert(EnrichmentWorkTables.deckMembership, {
      'species_id': 'sp-b',
      'deck_id': 'deck-1',
    });
    await database.insert(EnrichmentWorkTables.capabilityState, {
      'species_id': 'sp-a',
      'capability': 'speciesCommonNames',
      'state': 'pending',
      'priority_tier': 20,
      'attempt_count': 0,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkTables.capabilityState, {
      'species_id': 'sp-b',
      'capability': 'inatPrimary',
      'state': 'pending',
      'priority_tier': 10,
      'attempt_count': 0,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkTables.taxonomyWork, {
      'work_key': 'genus:acropora',
      'runtime_entity_key': 'genus:acropora',
      'common_names_state': 'pending',
      'attempt_count': 0,
      'updated_at': now,
    });
    await database.insert(EnrichmentWorkTables.taxonomyWorkSpecies, {
      'work_key': 'genus:acropora',
      'species_id': 'sp-a',
    });
    await database.insert(EnrichmentWorkTables.unresolvedNames, {
      'deck_id': 'deck-1',
      'name': 'Unknownus fishus',
      'state': 'pending',
      'attempt_count': 0,
      'updated_at': now,
    });

    // Priority order: inatPrimary (10) < speciesCommonNames (20) <
    // taxonomyCommonNames (30) < nameResolution (50).
    final first = await claims.claimNextINatWorkItem();
    expect(first!.kind, INatWorkItemKind.inatPrimary);
    expect(first.speciesId, 'sp-b');
    expect(first.priorityTier, 10);

    final second = await claims.claimNextINatWorkItem();
    expect(second!.kind, INatWorkItemKind.speciesCommonNames);
    expect(second.speciesId, 'sp-a');
    expect(second.priorityTier, 20);

    final third = await claims.claimNextINatWorkItem();
    expect(third!.kind, INatWorkItemKind.taxonomyCommonNames);
    expect(third.taxonomyWorkKey, 'genus:acropora');
    expect(third.taxonomyRuntimeEntityKey, 'genus:acropora');
    expect(third.taxonomySpeciesIds, {'sp-a'});
    expect(third.priorityTier, 30);

    final fourth = await claims.claimNextINatWorkItem();
    expect(fourth!.kind, INatWorkItemKind.nameResolution);
    expect(fourth.deckId, 'deck-1');
    expect(fourth.unresolvedName, 'Unknownus fishus');
    expect(fourth.priorityTier, 50);

    expect(await claims.claimNextINatWorkItem(), isNull);
  });

  test('claimNextINatWorkItem drains two freshly-queued decks by global tier '
      'then age, not one deck fully before the other', () async {
    final base = DateTime.now().millisecondsSinceEpoch;
    // Two decks queued at once. Species-scoped claims require a membership row
    // (see claimNextINatWorkItem's doc comment).
    await database.insert(EnrichmentWorkTables.deckMembership, {
      'species_id': 'sp-1',
      'deck_id': 'deck-1',
    });
    await database.insert(EnrichmentWorkTables.deckMembership, {
      'species_id': 'sp-2',
      'deck_id': 'deck-2',
    });
    await database.insert(EnrichmentWorkTables.deckMembership, {
      'species_id': 'sp-3',
      'deck_id': 'deck-1',
    });
    // deck-1's primary is the newer of the two same-tier primaries...
    await database.insert(EnrichmentWorkTables.capabilityState, {
      'species_id': 'sp-1',
      'capability': 'inatPrimary',
      'state': 'pending',
      'priority_tier': 10,
      'attempt_count': 0,
      'updated_at': base + 2,
    });
    // ...deck-2's is older, so it must be claimed first even though it belongs
    // to a different deck: within a tier the queue is globally age-ordered, no
    // deck is drained ahead of the other.
    await database.insert(EnrichmentWorkTables.capabilityState, {
      'species_id': 'sp-2',
      'capability': 'inatPrimary',
      'state': 'pending',
      'priority_tier': 10,
      'attempt_count': 0,
      'updated_at': base + 1,
    });
    // Oldest row overall, but a higher tier — tier dominates age, so it is
    // drained last despite being seeded first.
    await database.insert(EnrichmentWorkTables.capabilityState, {
      'species_id': 'sp-3',
      'capability': 'speciesCommonNames',
      'state': 'pending',
      'priority_tier': 20,
      'attempt_count': 0,
      'updated_at': base,
    });

    final first = await claims.claimNextINatWorkItem();
    expect(
      first!.speciesId,
      'sp-2',
      reason: 'older same-tier item wins across decks',
    );
    expect(first.priorityTier, 10);

    final second = await claims.claimNextINatWorkItem();
    expect(second!.speciesId, 'sp-1');
    expect(second.priorityTier, 10);

    final third = await claims.claimNextINatWorkItem();
    expect(
      third!.speciesId,
      'sp-3',
      reason: 'higher tier drained last despite being the oldest row',
    );
    expect(third.priorityTier, 20);

    expect(await claims.claimNextINatWorkItem(), isNull);
  });
}
