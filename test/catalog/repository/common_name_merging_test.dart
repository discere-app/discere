import 'package:discere/catalog/repository/common_name_merging.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a single column value', () {
    test('becomes a one-element list', () {
      expect(wrapName('Clownfish'), ['Clownfish']);
    });

    test('is dropped when null, blank or whitespace', () {
      expect(wrapName(null), isEmpty);
      expect(wrapName(''), isEmpty);
      expect(wrapName('   '), isEmpty);
    });

    test('keeps its inner spacing but loses the outer', () {
      expect(wrapName('  Clown  fish  '), ['Clown  fish']);
    });
  });

  group('reading the reference-DB columns', () {
    test('picks up one name per language', () {
      final names = localizedListMap({
        'common_name_en': 'Clownfish',
        'common_name_de': 'Clownfisch',
        'common_name_fr': null,
        'common_name_es': '',
      });

      expect(names[Language.en], ['Clownfish']);
      expect(names[Language.de], ['Clownfisch']);
      expect(names[Language.fr], isEmpty);
      expect(names[Language.es], isEmpty);
    });

    test('a missing row yields nothing rather than empty lists', () {
      expect(localizedListMap(null), isEmpty);
    });

    test('a prefixed ancestor name takes the first language that has one', () {
      expect(
        localizedName({
          'family_common_name_en': null,
          'family_common_name_de': 'Riffbarsche',
        }, 'family'),
        'Riffbarsche',
      );
    });

    test('an ancestor with no name anywhere yields null', () {
      expect(localizedName({'family_common_name_en': ''}, 'family'), isNull);
    });
  });

  group('a parent standing in for a child', () {
    test('is used only where the child has nothing', () {
      final merged = preferOwnNames(
        {Language.en: ['Clownfish'], Language.de: const []},
        {Language.en: ['Anemonefish'], Language.de: ['Anemonenfische']},
      );

      // Not appended: the inherited name belongs to a different taxon, so it
      // is a substitute, not a second name for the same thing.
      expect(merged[Language.en], ['Clownfish']);
      expect(merged[Language.de], ['Anemonenfische']);
    });

    test('leaves a language empty when neither has a name', () {
      final merged = preferOwnNames(const {}, const {});

      expect(merged[Language.fr], isEmpty);
    });
  });

  group('imported and reference names for the same taxon', () {
    test('imported come first, reference is appended', () {
      final merged = mergeLocalizedCommonNames(
        {Language.en: ['Clownfish']},
        {Language.en: ['Nemo', 'Anemonefish']},
      );

      expect(merged[Language.en], ['Nemo', 'Anemonefish', 'Clownfish']);
    });

    test('a name present in both appears once', () {
      final merged = mergeLocalizedCommonNames(
        {Language.en: ['Clownfish']},
        {Language.en: ['Clownfish', 'Nemo']},
      );

      expect(merged[Language.en], ['Clownfish', 'Nemo']);
    });

    test('every language is present even with no names at all', () {
      final merged = mergeLocalizedCommonNames(const {}, const {});

      expect(merged.keys, containsAll(Language.values));
    });
  });

  group('what counts as the same name', () {
    test('case does not distinguish two names', () {
      expect(mergeNameLists(['Clownfish'], ['clownfish']), ['Clownfish']);
    });

    test('nor does differing whitespace', () {
      expect(
        mergeNameLists(['Clown  fish'], [' clown fish ']),
        ['Clown  fish'],
      );
    });

    test('the first spelling is the one kept', () {
      expect(mergeNameLists(['CLOWNFISH'], ['Clownfish']), ['CLOWNFISH']);
    });

    test('blank entries are dropped', () {
      expect(mergeNameLists(['', '  '], ['Clownfish']), ['Clownfish']);
    });

    test('an empty side is returned as-is, without a pass over it', () {
      expect(mergeNameLists(const [], ['a', 'a']), ['a', 'a']);
      expect(mergeNameLists(['a', 'a'], const []), ['a', 'a']);
    });
  });

  group('runtime language codes', () {
    test('map to the language of the same name', () {
      expect(languageFromCode('de'), Language.de);
      expect(languageFromCode('es'), Language.es);
    });

    test('an unknown code is nothing, not a fallback', () {
      // Those names are simply not shown; guessing a language would put a
      // Japanese name under "English".
      expect(languageFromCode('ja'), isNull);
      expect(languageFromCode(''), isNull);
    });
  });
}
