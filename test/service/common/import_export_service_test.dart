import 'dart:convert';
import 'package:discere/model/biology/species.dart';
import 'package:discere/model/biology/classification.dart';
import 'package:discere/model/ui/create_deck.dart';
import 'package:discere/service/common/import_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  late MockDecksService mockDecksService;
  late MockSpeciesRepository mockSpeciesRepo;
  late ImportExportService service;

  setUp(() {
    mockDecksService = MockDecksService();
    mockSpeciesRepo = MockSpeciesRepository();
    service = ImportExportService(mockDecksService, mockSpeciesRepo);
  });

  group('ImportExportService - importDeckFromJson', () {
    test('should import deck from JSON and call createDeck', () async {
      final classification = Classification('', {}, null, '', {}, '', {}, '', {}, null);
      final species1 = Species('1', 'Species', '1', 'sp1', {}, classification, []);
      
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
}
