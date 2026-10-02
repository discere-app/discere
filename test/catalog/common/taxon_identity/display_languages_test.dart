import 'package:discere/catalog/common/taxon_identity/display_languages.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offers the languages the taxon has a common name in', () {
    final languages = selectableDisplayLanguages(const {
      Language.de: ['Weißer Hai'],
      Language.en: ['Great white shark'],
      Language.fr: [],
    }, Language.de);

    expect(languages, [Language.de, Language.en]);
  });

  test('keeps the current language even when the taxon has no name in it, '
      'so the checked entry never drops out of its own menu', () {
    final languages = selectableDisplayLanguages(const {
      Language.en: ['Great white shark'],
    }, Language.es);

    expect(languages, [Language.en, Language.es]);
  });

  test('offers only the current language for a taxon without any common '
      'name', () {
    expect(selectableDisplayLanguages(const {}, Language.fr), [Language.fr]);
  });
}
