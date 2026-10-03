import 'dart:convert';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/share/deck_export_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

/// Stands in for the system save dialog: records what it was handed and
/// answers with whatever the test set up.
class _FakeFileSaver {
  Future<Uri?> Function() answer = () async => null;
  String? fileName;
  Uint8List? bytes;
  String? mimeType;

  Future<Uri?> call({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) {
    this.fileName = fileName;
    this.bytes = bytes;
    this.mimeType = mimeType;
    return answer();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDecksService mockDecksService;
  late _FakeFileSaver fileSaver;
  late DeckExportService service;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          (methodCall) async => null,
        );
    mockDecksService = MockDecksService();
    fileSaver = _FakeFileSaver();
    service = DeckExportService(mockDecksService, fileSaver: fileSaver.call);
  });

  group('DeckExportService - saveJsonToFile', () {
    const jsonData = '{"name":"Grüne Riffe"}';

    Future<DeckFileSaveResult> save() => service.saveJsonToFile(
      jsonData: jsonData,
      deckName: 'Grüne Riffe',
      exportPrefix: 'discere',
    );

    test('hands the JSON to the save dialog as a UTF-8 .json file', () async {
      await save();

      expect(fileSaver.fileName, 'discere_Grüne_Riffe.json');
      expect(fileSaver.mimeType, 'application/json');
      expect(utf8.decode(fileSaver.bytes!), jsonData);
    });

    test('reports saved once the dialog returns where it wrote', () async {
      fileSaver.answer = () async => Uri.parse('content://downloads/1');

      expect(await save(), DeckFileSaveResult.saved);
    });

    test('reports cancelled when the user dismisses the dialog', () async {
      fileSaver.answer = () async => null;

      expect(await save(), DeckFileSaveResult.cancelled);
    });

    test('reports failed when the platform side throws', () async {
      fileSaver.answer = () async =>
          throw PlatformException(code: 'Error while saving file');

      expect(await save(), DeckFileSaveResult.failed);
    });
  });

  group('DeckExportService - sharing', () {
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
