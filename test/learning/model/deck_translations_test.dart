import 'dart:convert';

import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/deck_translations.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _deckJson({
  Object? translations,
  List<Map<String, dynamic>>? subdecks,
}) => {
  'name': 'Haie und Rochen',
  'description': 'Knorpelfische',
  'speciesNames': ['Carcharodon carcharias'],
  'translations': ?translations,
  'subdecks': ?subdecks,
};

Map<String, dynamic> _subdeckJson({Object? translations}) => {
  'id': 'level-1',
  'name': 'Level 1',
  'translations': ?translations,
  'speciesNames': ['Carcharodon carcharias'],
};

const _translations = {
  'en': {'name': 'Sharks and Rays', 'description': 'Cartilaginous fishes'},
  'fr': {'name': 'Requins et raies'},
};

/// The deck [json] reads as once resolved in [language].
CreateDeck _read(Map<String, dynamic> json, Language language) =>
    CreateDeck.fromJson(DeckTranslations.resolve(json, language));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeckTranslations.resolve', () {
    test('takes the texts in the given language', () {
      final deck = _read(_deckJson(translations: _translations), Language.en);

      expect(deck.name, 'Sharks and Rays');
      expect(deck.description, 'Cartilaginous fishes');
    });

    test('falls back to English for a language without translations', () {
      final deck = _read(_deckJson(translations: _translations), Language.es);

      expect(deck.name, 'Sharks and Rays');
      expect(deck.description, 'Cartilaginous fishes');
    });

    test('falls back to the untranslated texts without an English one', () {
      final deck = _read(
        _deckJson(
          translations: {
            'fr': {'name': 'Requins et raies'},
          },
        ),
        Language.es,
      );

      expect(deck.name, 'Haie und Rochen');
      expect(deck.description, 'Knorpelfische');
    });

    test('picks each field on its own', () {
      final deck = _read(_deckJson(translations: _translations), Language.fr);

      expect(deck.name, 'Requins et raies');
      expect(deck.description, 'Cartilaginous fishes');
    });

    test('a translated name keeps the untranslated description when '
        'English has none', () {
      final deck = _read(
        _deckJson(
          translations: {
            'fr': {'name': 'Requins et raies'},
          },
        ),
        Language.fr,
      );

      expect(deck.name, 'Requins et raies');
      expect(deck.description, 'Knorpelfische');
    });

    test('a deck without translations reads as it is', () {
      final json = _deckJson(subdecks: [_subdeckJson()]);

      expect(DeckTranslations.resolve(json, Language.fr), json);
    });

    group('subdecks', () {
      test('take their names in the given language', () {
        final deck = _read(
          _deckJson(
            subdecks: [
              _subdeckJson(
                translations: {
                  'de': {'name': 'Stufe 1'},
                },
              ),
            ],
          ),
          Language.de,
        );

        expect(deck.subdecks!.single.name, 'Stufe 1');
      });

      test('fall back to English, then to the untranslated name', () {
        final json = _deckJson(
          subdecks: [
            _subdeckJson(
              translations: {
                'en': {'name': 'Beginner'},
                'de': {'name': 'Stufe 1'},
              },
            ),
            {..._subdeckJson(), 'id': 'level-2', 'speciesNames': <String>[]},
          ],
        );

        final deck = _read(json, Language.fr);

        expect(deck.subdecks!.map((subdeck) => subdeck.name), [
          'Beginner',
          'Level 1',
        ]);
      });

      test('are resolved apart from the deck', () {
        final deck = _read(
          _deckJson(translations: _translations, subdecks: [_subdeckJson()]),
          Language.en,
        );

        expect(deck.name, 'Sharks and Rays');
        expect(deck.subdecks!.single.name, 'Level 1');
      });
    });

    test('leaves no translations behind, in the deck or its subdecks', () {
      final resolved = DeckTranslations.resolve(
        _deckJson(
          translations: _translations,
          subdecks: [
            _subdeckJson(
              translations: {
                'en': {'name': 'Beginner'},
              },
            ),
          ],
        ),
        Language.en,
      );

      expect(resolved, isNot(contains('translations')));
      expect(
        (resolved['subdecks'] as List).single,
        isNot(contains('translations')),
      );
    });

    test('leaves the given JSON as it is', () {
      final json = _deckJson(
        translations: _translations,
        subdecks: [
          _subdeckJson(
            translations: {
              'en': {'name': 'Beginner'},
            },
          ),
        ],
      );
      final before = jsonEncode(json);

      DeckTranslations.resolve(json, Language.en);

      expect(jsonEncode(json), before);
    });

    test('a deck read from translations shares only the texts it was read '
        'in', () {
      final deck = _read(_deckJson(translations: _translations), Language.fr);

      final shared = deck.toJson();

      expect(shared, isNot(contains('translations')));
      expect(shared['name'], 'Requins et raies');
      expect(shared['description'], 'Cartilaginous fishes');
    });

    group('skips a broken translation and reads the deck from the next '
        'step', () {
      final brokenFrench = <String, Object>{
        'a language that is no object': 'Requins et raies',
        'a number for a name': {'name': 42},
        'an empty name': {'name': ''},
        'a blank name': {'name': '  '},
      };
      for (final MapEntry(key: description, value: french)
          in brokenFrench.entries) {
        test(description, () {
          final deck = _read(
            _deckJson(
              translations: {
                'fr': french,
                'en': {'name': 'Sharks and Rays'},
              },
            ),
            Language.fr,
          );

          expect(deck.name, 'Sharks and Rays');
        });
      }

      test('translations that are no object', () {
        final deck = _read(
          _deckJson(translations: ['Sharks and Rays']),
          Language.en,
        );

        expect(deck.name, 'Haie und Rochen');
        expect(deck.description, 'Knorpelfische');
      });

      test('a language this app does not carry', () {
        final deck = _read(
          _deckJson(
            translations: {
              'it': {'name': 'Squali e razze'},
            },
          ),
          Language.en,
        );

        expect(deck.name, 'Haie und Rochen');
      });
    });
  });
}
