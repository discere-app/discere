import 'package:discere/model/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Language.fromValue', () {
    test('returns Language.de for value 0', () {
      expect(Language.fromValue(0), Language.de);
    });

    test('returns Language.en for value 1', () {
      expect(Language.fromValue(1), Language.en);
    });

    test('returns Language.fr for value 2', () {
      expect(Language.fromValue(2), Language.fr);
    });

    test('returns Language.es for value 3', () {
      expect(Language.fromValue(3), Language.es);
    });

    test('throws ArgumentError for an unknown value', () {
      expect(() => Language.fromValue(99), throwsA(isA<ArgumentError>()));
    });

    test('throws ArgumentError for a negative value', () {
      expect(() => Language.fromValue(-1), throwsA(isA<ArgumentError>()));
    });

    test('round-trips: fromValue(language.value) == language', () {
      for (final lang in Language.values) {
        expect(Language.fromValue(lang.value), lang);
      }
    });
  });

  group('Language.toLocale', () {
    test('Language.de produces Locale("de")', () {
      expect(Language.de.toLocale(), const Locale('de'));
    });

    test('Language.en produces Locale("en")', () {
      expect(Language.en.toLocale(), const Locale('en'));
    });

    test('Language.fr produces Locale("fr")', () {
      expect(Language.fr.toLocale(), const Locale('fr'));
    });

    test('Language.es produces Locale("es")', () {
      expect(Language.es.toLocale(), const Locale('es'));
    });
  });
}
