import 'dart:convert';
import 'dart:io';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/import/import_text_recognizer.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_serialization_worker.dart';
import 'package:discere/learning/share/deck_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const worker = DeckSerializationWorker();
  const recognizer = ImportTextRecognizer(worker);

  final deck = CreateDeck(
    name: 'Reef Sharks',
    description: 'Sharks of the reef',
    speciesNames: {'Carcharodon carcharias', 'Sphyrna mokarran'},
  );

  group('deck JSON', () {
    test('is recognized with its fields', () async {
      final result = await recognizer.recognize(jsonEncode(deck.toJson()));

      expect(result, isA<RecognizedDeckJson>());
      final recognized = (result as RecognizedDeckJson).deck;
      expect(recognized.name, 'Reef Sharks');
      expect(recognized.description, 'Sharks of the reef');
      expect(recognized.speciesNames, deck.speciesNames);
    });

    test('broken JSON is unrecognized, not a species list', () async {
      final result = await recognizer.recognize('{"name": "Reef Sharks",');

      expect(result, isA<UnrecognizedImport>());
    });

    test('a JSON object without deck fields is unrecognized', () async {
      final result = await recognizer.recognize('{"title": "Reef Sharks"}');

      expect(result, isA<UnrecognizedImport>());
    });

    test('a JSON array is unrecognized', () async {
      final result = await recognizer.recognize(jsonEncode([deck.toJson()]));

      expect(result, isA<UnrecognizedImport>());
    });
  });

  group('QR payload', () {
    test('is recognized with its fields', () async {
      final payload = await worker.encodeGzipBase64(deck.toJson());

      final result = await recognizer.recognize(payload);

      expect(result, isA<RecognizedQrPayload>());
      final recognized = (result as RecognizedQrPayload).deck;
      expect(recognized.name, 'Reef Sharks');
      expect(recognized.speciesNames, deck.speciesNames);
    });

    test('surrounding whitespace from a paste does not matter', () async {
      final payload = await worker.encodeGzipBase64(deck.toJson());

      final result = await recognizer.recognize('\n  $payload \n');

      expect(result, isA<RecognizedQrPayload>());
    });

    for (final (label, lineBreak) in [('LF', '\n'), ('CRLF', '\r\n')]) {
      test('wrapped every 76 characters with $label is recognized', () async {
        final payload = await worker.encodeGzipBase64(deck.toJson());
        final lines = [
          for (var i = 0; i < payload.length; i += 76)
            payload.substring(i, (i + 76).clamp(0, payload.length)),
        ];
        expect(lines.length, greaterThan(1), reason: 'payload must wrap');

        final result = await recognizer.recognize(lines.join(lineBreak));

        expect(result, isA<RecognizedQrPayload>());
        expect(
          (result as RecognizedQrPayload).deck.speciesNames,
          deck.speciesNames,
        );
      });
    }

    test('base64 without the gzip signature is unrecognized', () async {
      final result = await recognizer.recognize(
        base64Encode(utf8.encode(jsonEncode(deck.toJson()))),
      );

      expect(result, isA<UnrecognizedImport>());
    });

    test('gzip of something other than a deck is unrecognized', () async {
      final result = await recognizer.recognize(
        base64Encode(gzip.encode(utf8.encode('[1, 2, 3]'))),
      );

      expect(result, isA<UnrecognizedImport>());
    });
  });

  group('species list', () {
    Future<Set<String>?> namesOf(String text) async {
      final result = await recognizer.recognize(text);
      return result is RecognizedSpeciesList ? result.speciesNames : null;
    }

    test('a single word made of base64 characters is a species list', () async {
      // Letters alone are valid base64; only the missing gzip signature at
      // the head keeps these from being taken for a QR payload.
      expect(await namesOf('Amphiprion'), orderedEquals(['Amphiprion']));
      expect(
        await namesOf('Amphiprion ocellaris\nAbramis brama'),
        orderedEquals(['Amphiprion ocellaris', 'Abramis brama']),
      );
    });

    test('one name per line is recognized in input order', () async {
      expect(
        await namesOf('Sphyrna mokarran\nCarcharodon carcharias'),
        orderedEquals(['Sphyrna mokarran', 'Carcharodon carcharias']),
      );
    });

    test('skips blank lines and # comments', () async {
      expect(
        await namesOf(
          '# Sharks\n\nCarcharodon carcharias\n   \n# more\nSphyrna mokarran\n',
        ),
        orderedEquals(['Carcharodon carcharias', 'Sphyrna mokarran']),
      );
    });

    test('strips list markers', () async {
      expect(
        await namesOf(
          '- Carcharodon carcharias\n'
          '* Sphyrna mokarran\n'
          '• Prionace glauca\n'
          '1. Rhincodon typus\n'
          '12) Galeocerdo cuvier',
        ),
        orderedEquals([
          'Carcharodon carcharias',
          'Sphyrna mokarran',
          'Prionace glauca',
          'Rhincodon typus',
          'Galeocerdo cuvier',
        ]),
      );
    });

    test('collapses whitespace runs inside a name', () async {
      expect(
        await namesOf('Carcharodon \t  carcharias'),
        orderedEquals(['Carcharodon carcharias']),
      );
    });

    test('drops duplicates after normalizing, keeping the first', () async {
      expect(
        await namesOf(
          'Carcharodon carcharias\n'
          '- carcharodon  CARCHARIAS\n'
          'Sphyrna mokarran\n'
          'Carcharodon carcharias',
        ),
        orderedEquals(['Carcharodon carcharias', 'Sphyrna mokarran']),
      );
    });

    test('accepts Windows and old Mac line endings', () async {
      expect(
        await namesOf(
          'Carcharodon carcharias\r\nSphyrna mokarran\rPrionace glauca',
        ),
        orderedEquals([
          'Carcharodon carcharias',
          'Sphyrna mokarran',
          'Prionace glauca',
        ]),
      );
    });

    test('accepts hybrid signs, hyphens and dots', () async {
      expect(
        await namesOf(
          'Pomacanthus × Holacanthus\nCyprinus carpio var. koi\nPolygonia c-album',
        ),
        orderedEquals([
          'Pomacanthus × Holacanthus',
          'Cyprinus carpio var. koi',
          'Polygonia c-album',
        ]),
      );
    });

    test('keeps names as they are, author and all, if they pass', () async {
      // An author without year or brackets is just more words; resolving or
      // rejecting it is the catalog lookup's call, not the recognizer's.
      expect(
        await namesOf('Carcharodon carcharias Linnaeus'),
        orderedEquals(['Carcharodon carcharias Linnaeus']),
      );
    });

    test('a single implausible line rejects the whole list', () async {
      final result = await recognizer.recognize(
        'Carcharodon carcharias\nCarcharodon carcharias (Linnaeus, 1758)',
      );

      expect(result, isA<UnrecognizedImport>());
    });

    test('prose is unrecognized', () async {
      final result = await recognizer.recognize(
        'Hi! Here is my shark deck, have fun with it.',
      );

      expect(result, isA<UnrecognizedImport>());
    });

    test('only comments and blank lines is unrecognized', () async {
      final result = await recognizer.recognize('# nothing here\n\n');

      expect(result, isA<UnrecognizedImport>());
    });
  });

  test('empty text is unrecognized', () async {
    expect(await recognizer.recognize(''), isA<UnrecognizedImport>());
    expect(await recognizer.recognize('  \n '), isA<UnrecognizedImport>());
  });

  group('round trip from the app export', () {
    late MockDecksService decksService;
    late DeckExportService exportService;

    setUp(() {
      decksService = MockDecksService();
      exportService = DeckExportService(
        decksService,
        fileSaver: ({required fileName, required bytes, required mimeType}) =>
            fail('no export here saves a file'),
      );
      when(decksService.getCreateDeck('deck-1')).thenAnswer((_) async => deck);
    });

    test('JSON export comes back as the same deck', () async {
      final json = await exportService.exportDeckToJson('deck-1');

      final result = await recognizer.recognize(json);

      expect(result, isA<RecognizedDeckJson>());
      expect((result as RecognizedDeck).deck.speciesNames, deck.speciesNames);
    });

    test('QR export comes back as the same deck', () async {
      final payload = await exportService.exportDeckToGzip('deck-1');

      final result = await recognizer.recognize(payload);

      expect(result, isA<RecognizedQrPayload>());
      expect((result as RecognizedDeck).deck.speciesNames, deck.speciesNames);
    });

    test('species list export comes back as the same names', () async {
      final sharePlatform = _CapturingSharePlatform();
      SharePlatform.instance = sharePlatform;
      when(decksService.getSpeciesByDeckId('deck-1')).thenAnswer(
        (_) async => [
          _species('1', 'Carcharodon', 'carcharias'),
          _species('2', 'Sphyrna', 'mokarran'),
        ],
      );

      await exportService.shareDeckAsSpeciesListText(
        deckId: 'deck-1',
        deckName: 'Reef Sharks',
      );
      final result = await recognizer.recognize(sharePlatform.sharedText!);

      expect(result, isA<RecognizedSpeciesList>());
      expect(
        (result as RecognizedSpeciesList).speciesNames,
        orderedEquals(['Carcharodon carcharias', 'Sphyrna mokarran']),
      );
    });
  });
}

Species _species(String id, String genus, String epithet) {
  return Species(
    id,
    'ext-$id',
    'fishbase',
    epithet,
    const {},
    Classification(
      genus,
      const {},
      null,
      'Lamnidae',
      const {},
      'Lamniformes',
      const {},
      'Chondrichthyes',
      const {},
      null,
    ),
    const [],
  );
}

class _CapturingSharePlatform extends SharePlatform {
  String? sharedText;

  @override
  Future<ShareResult> share(ShareParams params) async {
    sharedText = params.text;
    return const ShareResult('success', ShareResultStatus.success);
  }
}
