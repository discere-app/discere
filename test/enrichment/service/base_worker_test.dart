import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/service/base_worker.dart';
import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../mocks.mocks.dart';

Species _species(String id, {bool withReferencePicture = true}) {
  return Species(
    id,
    id,
    'mockSource',
    'mockName',
    const {},
    Classification(
      '',
      const {},
      null,
      '',
      const {},
      '',
      const {},
      '',
      const {},
      null,
    ),
    withReferencePicture
        ? [
            Picture(
              id: '$id-pic',
              species: id,
              origin: 'fishbase',
              isUsable: 1,
              url: 'https://example.com/$id.jpg',
            ),
          ]
        : const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentWorkRepository workRepository;
  late MockEnrichmentService enrichmentService;
  late MockSpeciesRepository speciesRepository;
  late BaseWorker worker;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await openDatabase(inMemoryDatabasePath, version: 1);
    for (final assetPath in const [
      'assets/sql/user_db/tables/create_enrichment_species_work.sql',
      'assets/sql/user_db/tables/create_enrichment_taxonomy_work.sql',
      'assets/sql/user_db/tables/create_enrichment_species_capability_state.sql',
      'assets/sql/user_db/tables/create_enrichment_species_deck_membership.sql',
      'assets/sql/user_db/tables/create_enrichment_unresolved_names.sql',
    ]) {
      await database.execute(await rootBundle.loadString(assetPath));
    }
    workRepository = EnrichmentWorkRepository(database);
    enrichmentService = MockEnrichmentService();
    speciesRepository = MockSpeciesRepository();
    worker = BaseWorker(enrichmentService, workRepository, speciesRepository);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedSpecies(String speciesId) {
    return workRepository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-1': {speciesId},
      },
      prioritizedDeckIds: ['deck-1'],
    );
  }

  Future<Map<String, Object?>> loadCapability(
    String speciesId,
    String capability,
  ) async {
    final rows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
      where: 'species_id = ? AND capability = ?',
      whereArgs: [speciesId, capability],
    );
    return rows.isEmpty ? const {} : rows.single;
  }

  test(
    'a species with no reference picture at all falls back to iNat '
    'immediately, without ever calling downloadBaseImagesForSpecies',
    () async {
      await seedSpecies('sp-no-pic');
      when(speciesRepository.getSpecies(any)).thenAnswer(
        (_) async => {_species('sp-no-pic', withReferencePicture: false)},
      );

      final processedAny = await worker.runUntilIdle(shouldStop: () => false);

      expect(processedAny, isTrue);
      verifyNever(enrichmentService.downloadBaseImagesForSpecies(any));

      final base = await loadCapability('sp-no-pic', 'base');
      expect(base['state'], 'noResult');

      final inatPrimary = await loadCapability('sp-no-pic', 'inatPrimary');
      expect(inatPrimary['state'], 'pending');
      expect(inatPrimary['priority_tier'], 10);

      final inatBackfill = await loadCapability('sp-no-pic', 'inatBackfill');
      expect(inatBackfill['state'], 'pending');
      expect(inatBackfill['priority_tier'], 40);
    },
  );

  test('a successful download marks base done and seeds a low-priority '
      'backfill item, without touching inatPrimary', () async {
    await seedSpecies('sp-a');
    when(
      speciesRepository.getSpecies(any),
    ).thenAnswer((_) async => {_species('sp-a')});
    when(enrichmentService.downloadBaseImagesForSpecies(any)).thenAnswer(
      (_) async => const ImportEnrichmentSummary(
        imageSpeciesCount: 1,
        imageCount: 1,
        commonNameSpeciesCount: 0,
        commonNameCount: 0,
      ),
    );

    await worker.runUntilIdle(shouldStop: () => false);

    final base = await loadCapability('sp-a', 'base');
    expect(base['state'], 'done');

    final inatBackfill = await loadCapability('sp-a', 'inatBackfill');
    expect(inatBackfill['state'], 'pending');
    expect(inatBackfill['priority_tier'], 40);

    final inatPrimary = await loadCapability('sp-a', 'inatPrimary');
    expect(inatPrimary, isEmpty);
  });

  test('a download that keeps returning zero images retries with backoff below '
      'the attempt cap, without falling back to iNat yet', () async {
    await seedSpecies('sp-a');
    when(
      speciesRepository.getSpecies(any),
    ).thenAnswer((_) async => {_species('sp-a')});
    when(
      enrichmentService.downloadBaseImagesForSpecies(any),
    ).thenAnswer((_) async => ImportEnrichmentSummary.empty);

    for (var attempt = 0; attempt < 4; attempt++) {
      await worker.runUntilIdle(shouldStop: () => false);
      // Force the row immediately claimable again for the next attempt in
      // this test, rather than waiting out the real backoff duration.
      await database.update(
        EnrichmentWorkRepository.capabilityStateTable,
        {'next_attempt_at': null},
        where: "species_id = ? AND capability = 'base'",
        whereArgs: ['sp-a'],
      );
    }

    final base = await loadCapability('sp-a', 'base');
    expect(base['state'], 'retryScheduled');
    expect(base['attempt_count'], 4);

    final inatPrimary = await loadCapability('sp-a', 'inatPrimary');
    expect(inatPrimary, isEmpty);
  });

  test('a download that keeps failing gives up after the attempt cap and falls '
      'back to iNat', () async {
    await seedSpecies('sp-a');
    when(
      speciesRepository.getSpecies(any),
    ).thenAnswer((_) async => {_species('sp-a')});
    when(
      enrichmentService.downloadBaseImagesForSpecies(any),
    ).thenAnswer((_) async => ImportEnrichmentSummary.empty);

    for (var attempt = 0; attempt < 5; attempt++) {
      await worker.runUntilIdle(shouldStop: () => false);
      await database.update(
        EnrichmentWorkRepository.capabilityStateTable,
        {'next_attempt_at': null},
        where: "species_id = ? AND capability = 'base'",
        whereArgs: ['sp-a'],
      );
    }

    final base = await loadCapability('sp-a', 'base');
    expect(base['state'], 'permanentFailure');
    expect(base['attempt_count'], 5);

    final inatPrimary = await loadCapability('sp-a', 'inatPrimary');
    expect(inatPrimary['state'], 'pending');
    expect(inatPrimary['priority_tier'], 10);

    final inatBackfill = await loadCapability('sp-a', 'inatBackfill');
    expect(inatBackfill['state'], 'pending');
    expect(inatBackfill['priority_tier'], 40);
  });

  test('an exception from downloadBaseImagesForSpecies is treated the same as '
      'a zero-image result: retried, not thrown', () async {
    await seedSpecies('sp-a');
    when(
      speciesRepository.getSpecies(any),
    ).thenAnswer((_) async => {_species('sp-a')});
    when(
      enrichmentService.downloadBaseImagesForSpecies(any),
    ).thenThrow(StateError('boom'));

    final processedAny = await worker.runUntilIdle(shouldStop: () => false);

    expect(processedAny, isTrue);
    final base = await loadCapability('sp-a', 'base');
    expect(base['state'], 'retryScheduled');
    expect(base['attempt_count'], 1);
  });

  test('runUntilIdle returns false when there is no claimable work', () async {
    final processedAny = await worker.runUntilIdle(shouldStop: () => false);
    expect(processedAny, isFalse);
    verifyNever(speciesRepository.getSpecies(any));
  });

  test('runUntilIdle stops early once shouldStop returns true', () async {
    await seedSpecies('sp-a');

    final processedAny = await worker.runUntilIdle(shouldStop: () => true);

    expect(processedAny, isFalse);
    verifyNever(speciesRepository.getSpecies(any));
    final base = await loadCapability('sp-a', 'base');
    expect(base['state'], 'pending');
  });

  test('processes multiple claimed species in one runUntilIdle call', () async {
    await seedSpecies('sp-a');
    await seedSpecies('sp-b');
    when(speciesRepository.getSpecies(any)).thenAnswer((invocation) async {
      final ids = invocation.positionalArguments[0] as Set<String>;
      return ids.map((id) => _species(id)).toSet();
    });
    when(enrichmentService.downloadBaseImagesForSpecies(any)).thenAnswer(
      (_) async => const ImportEnrichmentSummary(
        imageSpeciesCount: 1,
        imageCount: 1,
        commonNameSpeciesCount: 0,
        commonNameCount: 0,
      ),
    );

    final processedAny = await worker.runUntilIdle(shouldStop: () => false);

    expect(processedAny, isTrue);
    expect((await loadCapability('sp-a', 'base'))['state'], 'done');
    expect((await loadCapability('sp-b', 'base'))['state'], 'done');
  });
}
