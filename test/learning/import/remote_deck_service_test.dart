import 'dart:convert';

import 'package:discere/learning/import/remote_deck_service.dart';
import 'package:discere/learning/model/deck_format.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RemoteDeckService', () {
    test('uses a patient default timeout for GitHub loading', () {
      final service = RemoteDeckService(
        client: http.Client(),
        appLanguage: () => Language.en,
      );

      expect(service.indexTimeout, const Duration(seconds: 20));
    });

    test('fetches all decks from a single index request', () async {
      var requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        expect(
          request.url.toString(),
          'https://raw.githubusercontent.com/discere-app/discere-data/main/data/decks/v2/index.json',
        );
        return http.Response(
          jsonEncode([
            {
              'name': 'Mittelmeer',
              'description': 'Fische im Mittelmeer',
              'speciesNames': ['Salpa salpa'],
            },
            {
              'name': 'Rotes Meer',
              'description': 'Fische im Roten Meer',
              'speciesNames': ['Pterois miles'],
            },
          ]),
          200,
        );
      });

      final service = RemoteDeckService(
        client: mockClient,
        appLanguage: () => Language.en,
      );
      final decks = await service.fetchRemoteDecks();

      expect(requestCount, 1);
      expect(decks, hasLength(2));
      expect(decks[0].name, 'Mittelmeer');
      expect(decks[1].name, 'Rotes Meer');
    });

    test('skips malformed entries without failing the whole list', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode([
            {'description': 'missing required name field'},
            {'name': 'Valid Deck', 'description': 'ok'},
          ]),
          200,
        );
      });

      final service = RemoteDeckService(
        client: mockClient,
        appLanguage: () => Language.en,
      );
      final decks = await service.fetchRemoteDecks();

      expect(decks, hasLength(1));
      expect(decks[0].name, 'Valid Deck');
    });

    test('reads the index of the newest format version the app reads', () {
      expect(
        AppConstants.deckCatalogIndexUrl,
        endsWith('/data/decks/v${DeckFormat.supportedVersion}/index.json'),
      );
    });

    group('translations', () {
      final entry = {
        'name': 'Haie und Rochen',
        'description': 'Knorpelfische',
        'translations': {
          'en': {
            'name': 'Sharks and Rays',
            'description': 'Cartilaginous fishes',
          },
        },
        'subdecks': [
          {
            'id': 'level-1',
            'name': 'Stufe 1',
            'translations': {
              'en': {'name': 'Level 1'},
            },
            'speciesNames': ['Carcharodon carcharias'],
          },
        ],
      };

      RemoteDeckService serviceIn(Language language) => RemoteDeckService(
        appLanguage: () => language,
        client: MockClient(
          (request) async => http.Response(jsonEncode([entry]), 200),
        ),
      );

      test('reads each deck in the app language', () async {
        final deck = (await serviceIn(Language.en).fetchRemoteDecks()).single;

        expect(deck.name, 'Sharks and Rays');
        expect(deck.description, 'Cartilaginous fishes');
        expect(deck.subdecks!.single.name, 'Level 1');
      });

      test('reads a deck not translated into the app language in '
          'English', () async {
        final deck = (await serviceIn(Language.es).fetchRemoteDecks()).single;

        expect(deck.name, 'Sharks and Rays');
        expect(deck.subdecks!.single.name, 'Level 1');
      });
    });

    group('format version', () {
      final newerVersion = DeckFormat.supportedVersion + 1;

      Map<String, Object?> entry(String name, [Object? formatVersion]) => {
        'name': name,
        'description': '',
        'speciesNames': ['Pterois miles'],
        'formatVersion': ?formatVersion,
      };

      RemoteDeckService serviceFor(List<Object?> entries) => RemoteDeckService(
        appLanguage: () => Language.en,
        client: MockClient(
          (request) async => http.Response(jsonEncode(entries), 200),
        ),
      );

      test('skips entries of a newer format and of a malformed version, '
          'keeping every readable one', () async {
        final decks = await serviceFor([
          entry('Without version'),
          entry('Version 1', 1),
          entry('Version 2', 2),
          entry('Newer', newerVersion),
          entry('Malformed', '2'),
        ]).fetchRemoteDecks();

        expect(decks.map((deck) => deck.name), [
          'Without version',
          'Version 1',
          'Version 2',
        ]);
      });

      test('an index of only newer entries is an empty list, not a format '
          'error', () async {
        final decks = await serviceFor([
          entry('Newer', newerVersion),
          entry('Newer still', newerVersion + 1),
        ]).fetchRemoteDecks();

        expect(decks, isEmpty);
      });

      test('an index of only malformed versions is a format error', () {
        expect(
          serviceFor([entry('Malformed', 2.5)]).fetchRemoteDecks(),
          throwsA(isA<DataFormatException>()),
        );
      });
    });
  });
}
