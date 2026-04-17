import 'dart:convert';

import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/shared/util/json_export_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

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
      expect(result.lastError, contains('failed-b'));
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
  });
}
