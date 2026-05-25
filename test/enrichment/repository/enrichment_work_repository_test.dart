import 'dart:convert';

import 'package:discere/enrichment/model/enrichment_work_plan.dart';
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
      expect(assignments['deck-active'], containsAll(['sp-shared', 'sp-active-only']));
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

      final succeeded = await repository
          .loadSucceededSpeciesIdsForStage(EnrichmentStage.base);
      expect(succeeded, {'sp-a', 'sp-c'});

      final otherStage = await repository
          .loadSucceededSpeciesIdsForStage(EnrichmentStage.inatPrimary);
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
}
