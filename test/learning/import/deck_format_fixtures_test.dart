/// Real decks of every format version the app has read, each as an author
/// wrote it: the app reads every older format for good, so each one has to
/// come through a shared import, the catalog and the import into the
/// database as the deck its file describes.
///
/// A new format version adds a file here. No file is ever deleted or
/// rewritten: a file that stops being read is a deck some user holds that
/// the app has stopped reading.
library;

import 'dart:convert';
import 'dart:io';

import 'package:discere/learning/import/import_text_recognizer.dart';
import 'package:discere/learning/import/remote_deck_service.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/deck_format.dart';
import 'package:discere/learning/service/deck_serialization_worker.dart';
import 'package:discere/learning/share/deck_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../../support/learning_test_stack.dart';

const _fixtureDir = 'test/fixtures/decks';

final _fixtures =
    Directory(_fixtureDir)
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// Every species of the deck [json] describes: its `speciesNames` and the
/// names of its subdecks.
Set<String> _speciesNamesOf(Map<String, dynamic> json) => {
  ...(json['speciesNames'] as List).cast<String>(),
  for (final subdeck in _subdecksOf(json))
    ...(subdeck['speciesNames'] as List).cast<String>(),
};

List<Map<String, dynamic>> _subdecksOf(Map<String, dynamic> json) =>
    ((json['subdecks'] as List?) ?? const []).cast<Map<String, dynamic>>();

/// Each subdeck as `id name: species`, comparable across reading and the
/// database.
List<String> _describeSubdecks(CreateDeck deck) => [
  for (final subdeck in deck.subdecks ?? const [])
    '${subdeck.id} ${subdeck.name}: ${subdeck.speciesNames.toSet()}',
];

List<String> _describeJsonSubdecks(Map<String, dynamic> json) => [
  for (final subdeck in _subdecksOf(json))
    '${subdeck['id']} ${subdeck['name']}: '
        '${(subdeck['speciesNames'] as List).cast<String>().toSet()}',
];

/// That [deck] is what the fixture [json] describes.
void _expectDeckOf(CreateDeck deck, Map<String, dynamic> json) {
  expect(deck.name, json['name']);
  expect(deck.description, json['description']);
  expect(deck.speciesNames, _speciesNamesOf(json));
  expect(_describeSubdecks(deck), _describeJsonSubdecks(json));
  expect(deck.supersedes, json['supersedes']);
  expect(deck.learningMode?.storageValue, json['learningMode']);
  expect(deck.nameType?.storageValue, json['nameType']);
  expect(deck.reviewMode?.storageValue, json['reviewMode']);
}

/// That [deck], shared again after importing the fixture [json], is the deck
/// it describes as far as sharing carries it: the catalog's `supersedes`
/// never travels, and the learning settings come from the sharer's deck
/// config, so only a setting the fixture makes has to survive.
void _expectSharedDeckOf(CreateDeck deck, Map<String, dynamic> json) {
  expect(deck.name, json['name']);
  expect(deck.description, json['description']);
  expect(deck.speciesNames, _speciesNamesOf(json));
  expect(_describeSubdecks(deck), _describeJsonSubdecks(json));
  expect(deck.supersedes, isNull);
  for (final (key, value) in [
    ('learningMode', deck.learningMode?.storageValue),
    ('nameType', deck.nameType?.storageValue),
    ('reviewMode', deck.reviewMode?.storageValue),
  ]) {
    if (json[key] != null) expect(value, json[key], reason: key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const worker = DeckSerializationWorker();
  const recognizer = ImportTextRecognizer(worker);

  test('every format version the app reads has a fixture deck', () {
    final versions = <int>{};
    for (final file in _fixtures) {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      switch (DeckFormat.declaredIn(json)) {
        case ReadableDeckFormat(:final version):
          versions.add(version);
        case final format:
          fail('${p.basename(file.path)} is not readable: $format');
      }
    }

    expect(
      [
        for (var version = 1; version <= DeckFormat.supportedVersion; version++)
          if (!versions.contains(version)) version,
      ],
      isEmpty,
      reason: 'format versions without a fixture deck',
    );
  });

  for (final file in _fixtures) {
    final name = p.basename(file.path);
    final text = file.readAsStringSync();
    final json = jsonDecode(text) as Map<String, dynamic>;

    group(name, () {
      test('is recognized as deck JSON', () async {
        final result = await recognizer.recognize(text);

        expect(result, isA<RecognizedDeckJson>());
        _expectDeckOf((result as RecognizedDeck).deck, json);
      });

      test('is recognized as a QR payload', () async {
        final payload = await worker.encodeGzipBase64(json);

        final result = await recognizer.recognize(payload);

        expect(result, isA<RecognizedQrPayload>());
        _expectDeckOf((result as RecognizedDeck).deck, json);
      });

      test('is imported with its species and subdecks', () async {
        final stack = await LearningTestStack.open();
        addTearDown(stack.close);
        final recognized = await recognizer.recognize(text);

        final result = await stack.importService.importDecks([
          (recognized as RecognizedDeck).deck,
        ]);

        expect(result.unresolvedNames, isEmpty);
        final imported = await stack.decksService.getCreateDeck(
          result.importedDeckIds.single,
        );
        expect(imported.speciesNames, _speciesNamesOf(json));
        expect(_describeSubdecks(imported), _describeJsonSubdecks(json));
      });

      test('is shared again in the format version it needs', () async {
        final stack = await LearningTestStack.open();
        addTearDown(stack.close);
        final recognized = await recognizer.recognize(text);
        final deckId = (await stack.importService.importDecks([
          (recognized as RecognizedDeck).deck,
        ])).importedDeckIds.single;
        final exportService = DeckExportService(
          stack.decksService,
          fileSaver: ({required fileName, required bytes, required mimeType}) =>
              fail('sharing as text saves no file'),
        );

        final exportedJson = await exportService.exportDeckToJson(deckId);
        final exportedPayload = await exportService.exportDeckToGzip(deckId);

        for (final exported in [
          jsonDecode(exportedJson) as Map<String, dynamic>,
          await worker.decodeGzipBase64(exportedPayload),
        ]) {
          if (json['subdecks'] == null) {
            expect(exported, isNot(contains('formatVersion')));
          } else {
            expect(exported['formatVersion'], 2);
          }
        }
        final fromJson = await recognizer.recognize(exportedJson);
        expect(fromJson, isA<RecognizedDeckJson>());
        _expectSharedDeckOf((fromJson as RecognizedDeck).deck, json);
        final fromPayload = await recognizer.recognize(exportedPayload);
        expect(fromPayload, isA<RecognizedQrPayload>());
        _expectSharedDeckOf((fromPayload as RecognizedDeck).deck, json);
      });
    });
  }

  test('a catalog index of all fixtures lists every deck', () async {
    final entries = [
      for (final file in _fixtures) jsonDecode(file.readAsStringSync()),
    ];
    final service = RemoteDeckService(
      client: MockClient(
        (request) async =>
            http.Response.bytes(utf8.encode(jsonEncode(entries)), 200),
      ),
    );

    final decks = await service.fetchRemoteDecks();

    expect(decks, hasLength(entries.length));
    for (final (index, deck) in decks.indexed) {
      _expectDeckOf(deck, entries[index] as Map<String, dynamic>);
    }
  });
}
