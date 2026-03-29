import 'dart:convert';
import 'package:discere/model/biology/species.dart';
import 'package:discere/model/biology/classification.dart';
import 'package:discere/model/ui/create_deck.dart';
import 'package:discere/service/common/import_export_service.dart';
import 'package:discere/util/json_export_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDecksService mockDecksService;
  late MockSpeciesRepository mockSpeciesRepo;
  late MockImageService mockImageService;
  late ImportExportService service;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (methodCall) async => null,
    );
    mockDecksService = MockDecksService();
    mockSpeciesRepo = MockSpeciesRepository();
    mockImageService = MockImageService();
    service = ImportExportService(mockDecksService, mockSpeciesRepo, mockImageService);
  });

  group('ImportExportService - importDeckFromJson', () {
    test('should import deck from JSON and call createDeck', () async {

      when(mockSpeciesRepo.getSpeciesIdsByFullNames(['Species 1']))
          .thenAnswer((_) async => {'1'});
      
      final createDeck = CreateDeck(
        name: 'Test JSON Deck',
        description: 'Imported via JSON',
        speciesNames: {'Species 1'},
      );
      final jsonStr = jsonEncode(createDeck.toJson());

      await service.importDeckFromJson(jsonStr);

      final captured = verify(mockDecksService.createDeck(captureAny)).captured.single as CreateDeck;
      expect(captured.name, 'Test JSON Deck');
      expect(captured.speciesIds, contains('1'));
    });

    test('should download deck cover if imageUrl is present', () async {
      when(mockSpeciesRepo.getSpeciesIdsByFullNames(any))
          .thenAnswer((_) async => {});
      when(mockImageService.downloadAndSaveDeckCover('https://example.com/image.jpg'))
          .thenAnswer((_) async => '/local/path/image.jpg');

      final createDeck = CreateDeck(
        name: 'Image Deck',
        description: 'Desc',
        imageUrl: 'https://example.com/image.jpg',
      );
      final jsonStr = jsonEncode(createDeck.toJson());

      await service.importDeckFromJson(jsonStr);

      verify(mockImageService.downloadAndSaveDeckCover('https://example.com/image.jpg')).called(1);
      final captured = verify(mockDecksService.createDeck(captureAny)).captured.single as CreateDeck;
      expect(captured.coverImagePath, '/local/path/image.jpg');
    });
  });

  group('ImportExportService - importDeckFromGzip', () {
    test('should import deck from GZIP and call createDeck', () async {
      final createDeck = CreateDeck(
        name: 'Test GZIP Deck',
        description: 'Imported via GZIP',
        speciesNames: {'Species 1'},
      );
      final gzipStr = JsonExportUtil.encode(createDeck);

      when(mockSpeciesRepo.getSpeciesIdsByFullNames(['Species 1']))
          .thenAnswer((_) async => {'id-gz-1'});

      await service.importDeckFromGzip(gzipStr);

      final captured = verify(mockDecksService.createDeck(captureAny)).captured.single as CreateDeck;
      expect(captured.name, 'Test GZIP Deck');
      expect(captured.speciesIds, contains('id-gz-1'));
    });
  });

  group('ImportExportService - importDeckFromSpeciesNames', () {
    test('should resolve names and call createDeck', () async {
      when(mockSpeciesRepo.getSpeciesIdsByFullNames(['Species 1', 'Species 2']))
          .thenAnswer((_) async => {'id1', 'id2'});

      await service.importDeckFromSpeciesNames(
        name: 'New Deck',
        description: 'Desc',
        scientificNames: ['Species 1', 'Species 2'],
      );

      final captured = verify(mockDecksService.createDeck(captureAny)).captured.single as CreateDeck;
      expect(captured.name, 'New Deck');
      expect(captured.speciesIds, containsAll(['id1', 'id2']));
    });
  });
  group('ImportExportService - sharing', () {
    test('shareDeckAsSpeciesListText should call getSpeciesByDeckId', () async {
      final classification = Classification('', {}, null, '', {}, '', {}, '', {}, null);
      final species1 = Species('1', 'Species 1', '1', 'sp1', {}, classification, []);

      when(mockDecksService.getSpeciesByDeckId('id1'))
          .thenAnswer((_) async => [species1]);

      await service.shareDeckAsSpeciesListText(
        deckId: 'id1',
        deckName: 'Test Deck',
      );

      verify(mockDecksService.getSpeciesByDeckId('id1')).called(1);
    });

    test('shareDeckAsJsonText should call getCreateDeck', () async {
      when(mockDecksService.getCreateDeck('id1'))
          .thenAnswer((_) async => CreateDeck(name: 'T', description: 'D'));

      await service.shareDeckAsJsonText(
        deckId: 'id1',
        deckName: 'Test Deck',
      );

      verify(mockDecksService.getCreateDeck('id1')).called(1);
    });
  });
}
