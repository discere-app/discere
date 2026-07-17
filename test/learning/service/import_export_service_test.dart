import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/import_export_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDecksService mockDecksService;
  late ImportExportService service;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          (methodCall) async => null,
        );
    mockDecksService = MockDecksService();
    service = ImportExportService(mockDecksService);
  });

  group('ImportExportService - sharing', () {
    test('shareDeckAsSpeciesListText should call getSpeciesByDeckId', () async {
      final classification = Classification(
        '',
        {},
        null,
        '',
        {},
        '',
        {},
        '',
        {},
        null,
      );
      final species1 = Species(
        '1',
        'Species 1',
        '1',
        'sp1',
        {},
        classification,
        [],
      );

      when(
        mockDecksService.getSpeciesByDeckId('id1'),
      ).thenAnswer((_) async => [species1]);

      await service.shareDeckAsSpeciesListText(
        deckId: 'id1',
        deckName: 'Test Deck',
      );

      verify(mockDecksService.getSpeciesByDeckId('id1')).called(1);
    });

    test('shareDeckAsJsonText should call getCreateDeck', () async {
      when(
        mockDecksService.getCreateDeck('id1'),
      ).thenAnswer((_) async => CreateDeck(name: 'T', description: 'D'));

      await service.shareDeckAsJsonText(deckId: 'id1', deckName: 'Test Deck');

      verify(mockDecksService.getCreateDeck('id1')).called(1);
    });
  });
}
