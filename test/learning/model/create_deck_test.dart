import 'dart:convert';

import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/create_subdeck.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _deckJson({
  List<String> speciesNames = const ['Aa aa', 'Bb bb'],
  List<Map<String, dynamic>>? subdecks,
  List<String>? supersedes,
}) => {
  'name': 'Red Sea',
  'description': 'Fishes',
  'sourceId': 'red-sea',
  'speciesNames': speciesNames,
  'subdecks': ?subdecks,
  'supersedes': ?supersedes,
};

/// Records compare their fields with `==`, which for a set is identity.
String _describe(CreateSubdeck subdeck) =>
    '${subdeck.id} ${subdeck.name}: ${subdeck.speciesNames.join(', ')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CreateDeck.fromJson', () {
    test('reads a deck without subdecks as before', () {
      final deck = CreateDeck.fromJson(_deckJson());

      expect(deck.subdecks, isNull);
      expect(deck.supersedes, isNull);
      expect(deck.speciesNames, {'Aa aa', 'Bb bb'});
    });

    test('reads subdecks and supersedes', () {
      final deck = CreateDeck.fromJson(
        _deckJson(
          subdecks: [
            {
              'id': 'l1',
              'name': 'Level 1',
              'speciesNames': ['Aa aa'],
            },
            {
              'id': 'l2',
              'name': 'Level 2',
              'speciesNames': ['Bb bb'],
            },
          ],
          supersedes: ['red-sea-1', 'red-sea-2'],
        ),
      );

      expect(deck.subdecks!.map(_describe), [
        'l1 Level 1: Aa aa',
        'l2 Level 2: Bb bb',
      ]);
      expect(deck.supersedes, ['red-sea-1', 'red-sea-2']);
    });

    test('a subdeck name missing from speciesNames still belongs to the '
        'deck', () {
      final deck = CreateDeck.fromJson(
        _deckJson(
          speciesNames: ['Aa aa'],
          subdecks: [
            {
              'id': 'l1',
              'name': 'Level 1',
              'speciesNames': ['Cc cc'],
            },
          ],
        ),
      );

      expect(deck.speciesNames, {'Aa aa', 'Cc cc'});
    });

    test('a name in two subdecks stays in the first only', () {
      final deck = CreateDeck.fromJson(
        _deckJson(
          subdecks: [
            {
              'id': 'l1',
              'name': 'Level 1',
              'speciesNames': ['Aa aa'],
            },
            {
              'id': 'l2',
              'name': 'Level 2',
              'speciesNames': ['Aa aa', 'Bb bb'],
            },
          ],
        ),
      );

      expect(deck.subdecks![0].speciesNames, {'Aa aa'});
      expect(deck.subdecks![1].speciesNames, {'Bb bb'});
    });

    test('of two subdecks with one id the first is kept, the species of the '
        'second staying in the deck', () {
      final deck = CreateDeck.fromJson(
        _deckJson(
          speciesNames: ['Aa aa'],
          subdecks: [
            {
              'id': 'l1',
              'name': 'Level 1',
              'speciesNames': ['Aa aa'],
            },
            {
              'id': 'l1',
              'name': 'Level 1 again',
              'speciesNames': ['Cc cc'],
            },
          ],
        ),
      );

      expect(deck.subdecks!.map((s) => s.name), ['Level 1']);
      expect(deck.speciesNames, {'Aa aa', 'Cc cc'});
    });
  });

  group('CreateDeck.toJson', () {
    test('a deck without subdecks has no subdecks key', () {
      final json = CreateDeck(
        name: 'Flat',
        description: '',
        speciesNames: {'Aa aa'},
      ).toJson();

      expect(json.containsKey('subdecks'), isFalse);
    });

    test('leaves supersedes out: it refers to the catalog', () {
      final json = CreateDeck.fromJson(
        _deckJson(supersedes: ['red-sea-1']),
      ).toJson();

      expect(json.containsKey('supersedes'), isFalse);
    });

    test('a deck read back from its JSON has the same subdecks', () {
      final original = CreateDeck.fromJson(
        _deckJson(
          subdecks: [
            {
              'id': 'l1',
              'name': 'Level 1',
              'speciesNames': ['Aa aa'],
            },
            {
              'id': 'l2',
              'name': 'Level 2',
              'speciesNames': ['Bb bb'],
            },
          ],
        ),
      );

      final roundTripped = CreateDeck.fromJsonString(
        jsonEncode(original.toJson()),
      );

      expect(
        roundTripped.subdecks!.map(_describe),
        original.subdecks!.map(_describe),
      );
      expect(roundTripped.speciesNames, original.speciesNames);
    });
  });
}
