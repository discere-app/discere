import 'dart:convert';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/deck_update_diff.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/shared/util/json_export_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

Species _species(String id, String genus, String epithet) {
  return Species(
    id,
    id,
    'fishbase',
    epithet,
    const {},
    Classification(
      genus,
      const {},
      null,
      'Family',
      const {},
      'Order',
      const {},
      'Class',
      const {},
      null,
    ),
    const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDecksService mockDecksService;
  late MockSpeciesRepository mockSpeciesRepo;
  late MockINaturalistService mockINatService;
  late DeckImportService service;

  setUp(() {
    mockDecksService = MockDecksService();
    mockSpeciesRepo = MockSpeciesRepository();
    mockINatService = MockINaturalistService();
    service = DeckImportService(
      mockDecksService,
      mockSpeciesRepo,
      iNatService: mockINatService,
    );
  });

  group('DeckImportService', () {
    test('importJson resolves species and creates deck', () async {
      when(
        mockSpeciesRepo.resolveFullNames(['Species 1']),
      ).thenAnswer((_) async => {'Species 1': '1'});
      when(mockDecksService.createDeck(any)).thenAnswer((_) async => 'deck-1');

      final createDeck = CreateDeck(
        name: 'Test JSON Deck',
        description: 'Imported via JSON',
        speciesNames: {'Species 1'},
      );

      final result = await service.importJson(jsonEncode(createDeck.toJson()));

      expect(result.importedDeckIds, ['deck-1']);
      expect(result.lastError, isNull);
      expect(result.attemptedCount, 1);
      expect(result.allSucceeded, isTrue);

      final captured =
          verify(mockDecksService.createDeck(captureAny)).captured.single
              as CreateDeck;
      expect(captured.name, 'Test JSON Deck');
      expect(captured.speciesIds, contains('1'));
    });

    test('importJson returns imported deck image URL metadata', () async {
      when(mockSpeciesRepo.resolveFullNames(any)).thenAnswer((_) async => {});
      when(
        mockINatService.searchTaxa(any, perPage: anyNamed('perPage')),
      ).thenAnswer((_) async => const []);
      when(mockDecksService.createDeck(any)).thenAnswer((_) async => 'deck-1');

      final createDeck = CreateDeck(
        name: 'Image Deck',
        description: 'Desc',
        imageUrl: 'https://example.com/image.jpg',
      );

      final result = await service.importJson(jsonEncode(createDeck.toJson()));

      expect(result.importedDeckIds, ['deck-1']);
      expect(result.imageUrlByDeckId, {
        'deck-1': 'https://example.com/image.jpg',
      });
      final captured =
          verify(mockDecksService.createDeck(captureAny)).captured.single
              as CreateDeck;
      expect(captured.coverImagePath, isNull);
    });

    test('importGzip resolves deck and creates it', () async {
      when(
        mockSpeciesRepo.resolveFullNames(['Species 1']),
      ).thenAnswer((_) async => {'Species 1': 'id-gz-1'});
      when(mockDecksService.createDeck(any)).thenAnswer((_) async => 'deck-gz');

      final createDeck = CreateDeck(
        name: 'Test GZIP Deck',
        description: 'Imported via GZIP',
        speciesNames: {'Species 1'},
      );

      final deckId = await service.importGzip(
        JsonExportUtil.encode(createDeck),
      );

      expect(deckId, 'deck-gz');
      final captured =
          verify(mockDecksService.createDeck(captureAny)).captured.single
              as CreateDeck;
      expect(captured.name, 'Test GZIP Deck');
      expect(captured.speciesIds, contains('id-gz-1'));
    });

    test(
      'importDeckFromSpeciesNames resolves names and creates deck',
      () async {
        when(
          mockSpeciesRepo.getSpeciesIdsByFullNames(['Species 1', 'Species 2']),
        ).thenAnswer((_) async => {'id1', 'id2'});
        when(
          mockDecksService.createDeck(any),
        ).thenAnswer((_) async => 'deck-ids');

        final deckId = await service.importDeckFromSpeciesNames(
          name: 'New Deck',
          description: 'Desc',
          scientificNames: ['Species 1', 'Species 2'],
        );

        expect(deckId, 'deck-ids');
        final captured =
            verify(mockDecksService.createDeck(captureAny)).captured.single
                as CreateDeck;
        expect(captured.name, 'New Deck');
        expect(captured.speciesIds, containsAll(['id1', 'id2']));
      },
    );

    test(
      'importJson resolves synonyms locally via the reference lookup',
      () async {
        when(
          mockSpeciesRepo.resolveFullNames(['Thymallus aeliani']),
        ).thenAnswer((_) async => {'Thymallus aeliani': 'species-1'});
        when(
          mockDecksService.createDeck(any),
        ).thenAnswer((_) async => 'deck-1');

        final createDeck = CreateDeck(
          name: 'Synonym Deck',
          description: 'Imported via JSON',
          speciesNames: {'Thymallus aeliani'},
        );

        final result = await service.importJson(
          jsonEncode(createDeck.toJson()),
        );

        expect(result.importedDeckIds, ['deck-1']);
        expect(result.unresolvedNames, isEmpty);
        verifyNever(mockINatService.searchTaxa(any));

        final captured =
            verify(mockDecksService.createDeck(captureAny)).captured.single
                as CreateDeck;
        expect(captured.speciesIds, contains('species-1'));
      },
    );

    test('importDecks aggregates successes and failures', () async {
      final firstDeck = CreateDeck(name: 'A', description: 'desc');
      final secondDeck = CreateDeck(name: 'B', description: 'desc');

      when(mockSpeciesRepo.resolveFullNames(any)).thenAnswer((_) async => {});
      when(mockDecksService.createDeck(any)).thenAnswer((invocation) async {
        final deck = invocation.positionalArguments.first as CreateDeck;
        if (deck.name == 'A') {
          return 'deck-a';
        }
        throw Exception('failed-b');
      });

      final result = await service.importDecks([firstDeck, secondDeck]);

      expect(result.importedDeckIds, ['deck-a']);
      expect(result.lastError.toString(), contains('failed-b'));
      expect(result.attemptedCount, 2);
      expect(result.allSucceeded, isFalse);
    });

    test('importJson returns error result when payload is invalid', () async {
      final result = await service.importJson('invalid');

      expect(result.importedDeckIds, isEmpty);
      expect(result.lastError, isNotNull);
      expect(result.attemptedCount, 1);
      expect(result.allSucceeded, isFalse);
    });

    test(
      'diffForUpdate reports added, removed and unresolved species',
      () async {
        final speciesA = _species('id-a', 'Genus', 'a');
        final speciesB = _species('id-b', 'Genus', 'b');
        final speciesC = _species('id-c', 'Genus', 'c');

        when(
          mockDecksService.getSpeciesByDeckId('deck-1'),
        ).thenAnswer((_) async => [speciesA, speciesB]);
        when(
          mockSpeciesRepo.resolveFullNames(['Genus a', 'Genus c', 'Genus x']),
        ).thenAnswer((_) async => {'Genus a': 'id-a', 'Genus c': 'id-c'});
        when(
          mockDecksService.getSpeciesByIds({'id-c'}),
        ).thenAnswer((_) async => [speciesC]);

        final remote = CreateDeck(
          name: 'Remote Deck',
          description: 'desc',
          speciesNames: {'Genus a', 'Genus c', 'Genus x'},
          sourceId: 'src-1',
          updatedAt: DateTime.utc(2026, 2, 1),
        );

        final diff = await service.diffForUpdate('deck-1', remote);

        expect(diff.addedSpecies.map((s) => s.id), ['id-c']);
        expect(diff.removedSpecies.map((s) => s.id), ['id-b']);
        expect(diff.unresolvedAddedNames, ['Genus x']);
        expect(diff.hasChanges, isTrue);
      },
    );

    test(
      'applyDeckUpdate with additions only keeps existing species, adds new ones, bumps sourceId/updatedAt',
      () async {
        final diff = DeckUpdateDiff(
          addedSpecies: [_species('id-c', 'Genus', 'c')],
          removedSpecies: [_species('id-b', 'Genus', 'b')],
          unresolvedAddedNames: ['Genus x'],
        );
        final remote = CreateDeck(
          name: 'Remote Deck',
          description: 'desc',
          sourceId: 'src-new',
          updatedAt: DateTime.utc(2026, 2, 1),
        );
        when(mockDecksService.getCreateDeck('deck-1')).thenAnswer(
          (_) async => CreateDeck(
            id: 'deck-1',
            name: 'Local Deck',
            description: 'local desc',
            speciesIds: {'id-a', 'id-b'},
            sourceId: 'src-old',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        when(mockDecksService.updateDeck(any, any)).thenAnswer((_) async {});

        final unresolved = await service.applyDeckUpdate(
          deckId: 'deck-1',
          remote: remote,
          diff: diff,
          includeAdditions: true,
          includeRemovals: false,
        );

        expect(unresolved, ['Genus x']);
        final captured = verify(
          mockDecksService.updateDeck(captureAny, captureAny),
        ).captured;
        final updatedDeck = captured[0] as dynamic;
        final newSpeciesIds = captured[1] as Set<String>;
        expect(updatedDeck.name, 'Local Deck');
        expect(updatedDeck.description, 'local desc');
        expect(updatedDeck.sourceId, 'src-new');
        expect(updatedDeck.updatedAt, DateTime.utc(2026, 2, 1));
        expect(newSpeciesIds, {'id-a', 'id-b', 'id-c'});
      },
    );

    test(
      'applyDeckUpdate with removals only drops species and returns no unresolved names',
      () async {
        final diff = DeckUpdateDiff(
          addedSpecies: [_species('id-c', 'Genus', 'c')],
          removedSpecies: [_species('id-b', 'Genus', 'b')],
          unresolvedAddedNames: ['Genus x'],
        );
        final remote = CreateDeck(
          name: 'Remote Deck',
          description: 'desc',
          sourceId: 'src-new',
          updatedAt: DateTime.utc(2026, 2, 1),
        );
        when(mockDecksService.getCreateDeck('deck-1')).thenAnswer(
          (_) async => CreateDeck(
            id: 'deck-1',
            name: 'Local Deck',
            description: 'local desc',
            speciesIds: {'id-a', 'id-b'},
            sourceId: 'src-old',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        when(mockDecksService.updateDeck(any, any)).thenAnswer((_) async {});

        final unresolved = await service.applyDeckUpdate(
          deckId: 'deck-1',
          remote: remote,
          diff: diff,
          includeAdditions: false,
          includeRemovals: true,
        );

        expect(unresolved, isEmpty);
        final captured = verify(
          mockDecksService.updateDeck(captureAny, captureAny),
        ).captured;
        final newSpeciesIds = captured[1] as Set<String>;
        expect(newSpeciesIds, {'id-a'});
      },
    );
  });
}
