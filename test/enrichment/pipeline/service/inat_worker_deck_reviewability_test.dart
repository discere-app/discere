import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_worker.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite/sqflite.dart';

import '../../../mocks.mocks.dart';
import '../../../support/in_memory_user_database.dart';

/// Mirrors `_DeckSpeciesMutationAdapter` in lib/app/wiring/enrichment_wiring.dart
/// exactly — the real port implementation that connects `INatWorker`'s name
/// resolution back to `DecksService`, so this test exercises the actual
/// production wiring rather than a fake standing in for it.
class _DeckSpeciesMutationAdapter implements DeckSpeciesMutationPort {
  final DecksService _decksService;
  const _DeckSpeciesMutationAdapter(this._decksService);

  @override
  Future<void> addSpeciesToDeck(String deckId, Set<String> speciesIds) {
    return _decksService.addSpeciesToDeck(deckId, speciesIds);
  }
}

class _FakeNameResolutionPort implements ScientificNameResolutionPort {
  final Map<String, String> resolutions;
  const _FakeNameResolutionPort(this.resolutions);

  @override
  Future<Map<String, String>> resolveNames(List<String> names) async {
    return {
      for (final name in names)
        if (resolutions.containsKey(name)) name: resolutions[name]!,
    };
  }
}

/// Covers the gap identified while investigating a real bug report: a deck
/// imported with species names that don't resolve against the local
/// reference DB (e.g. an "online deck" whose species are covered by
/// iNaturalist but not by the bundled FishBase/SeaLifeBase data) ends up with
/// zero `flashcard_stats` rows at creation time — the deck is only ever
/// reviewable if the *separate* asynchronous name-resolution path
/// (`INatWorker._processNameResolution` -> `DeckSpeciesMutationPort`
/// -> `DecksService.addSpeciesToDeck`) actually completes and writes back.
///
/// Every individual link in this chain already had unit coverage in
/// isolation (deck_import_service_test.dart mocks away what happens to
/// unresolved names; inat_worker_test.dart verifies the port is *called*,
/// but against a fake port that only records the call). Nothing exercised
/// the real `DecksService`-backed port end-to-end, which is exactly where a
/// production regression could hide — this test closes that gap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentWorkRepository workRepository;
  late DecksService decksService;
  late MockINatPhotoEnrichmentService photoEnrichmentService;
  late MockSpeciesCommonNameEnrichmentService commonNameEnrichmentService;
  late MockTaxonomyCommonNameEnrichmentService taxonomyService;
  late MockINatPhotoCacheRepository photoCacheRepository;

  setUp(() async {
    database = await openInMemoryUserDatabase();

    workRepository = EnrichmentWorkRepository(database);
    decksService = DecksService(
      DeckRepository(database: database),
      FlashcardStatRepository(database: database),
      MockSpeciesRepository(),
      MockImageService(),
    );

    photoEnrichmentService = MockINatPhotoEnrichmentService();
    commonNameEnrichmentService = MockSpeciesCommonNameEnrichmentService();
    taxonomyService = MockTaxonomyCommonNameEnrichmentService();
    photoCacheRepository = MockINatPhotoCacheRepository();
    when(
      taxonomyService.buildTaxonomyWorkPlanForSpecies(any),
    ).thenAnswer((_) async => const []);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'a deck created with zero locally-resolved species becomes reviewable '
    'once iNat resolves its unresolved name',
    () async {
      // Mirrors DeckImportService._resolveSpeciesIds bailing out with an
      // empty speciesIds set when none of the imported names matched the
      // local reference DB — exactly the "Critter" deck scenario.
      final deckId = await decksService.createDeck(
        CreateDeck(name: 'Critter', description: 'Imported online'),
      );

      expect(await decksService.getSpeciesByDeckId(deckId), isEmpty);

      await database.insert(EnrichmentWorkRepository.unresolvedNamesTable, {
        'deck_id': deckId,
        'name': 'Chromodoris willani',
        'state': 'pending',
        'wants_inat_photos': 1,
        'wants_common_names': 1,
        'attempt_count': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      final worker = INatWorker(
        photoEnrichmentService,
        commonNameEnrichmentService,
        taxonomyService,
        workRepository,
        photoCacheRepository,
        diagnostics: LocalDiagnostics(enabled: false),
        nameResolutionPort: const _FakeNameResolutionPort({
          'Chromodoris willani': 'sp-willani',
        }),
        deckSpeciesMutationPort: _DeckSpeciesMutationAdapter(decksService),
      );

      final processedAny = await worker.runUntilIdle(shouldStop: () => false);
      expect(processedAny, isTrue);

      final reviewableSpeciesIds = await decksService.getSpeciesIdsByDeckIds([
        deckId,
      ]);
      expect(
        reviewableSpeciesIds,
        {'sp-willani'},
        reason:
            'DecksService.addSpeciesToDeck should have created a '
            'flashcard_stats row once the name resolved — otherwise the '
            'deck stays permanently empty in DeckPage despite enrichment '
            'having "completed" successfully',
      );
    },
  );
}
