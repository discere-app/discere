import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveCommonNames', () {
    test('uses selected-language names without appending English fallback', () {
      final names = resolveCommonNames(const {
        Language.de: ['Falscher Clownfisch'],
        Language.en: ['Clown anemonefish', 'False clownfish'],
      }, Language.de);

      expect(names, ['Falscher Clownfisch']);
    });

    test('falls back to English when selected language is missing', () {
      final names = resolveCommonNames(const {
        Language.en: ['Clown anemonefish', 'False clownfish'],
      }, Language.de);

      expect(names, ['Clown anemonefish', 'False clownfish']);
    });

    test('falls back to English when selected language is empty', () {
      final names = resolveCommonNames(const {
        Language.de: [],
        Language.en: ['Clown anemonefish'],
      }, Language.de);

      expect(names, ['Clown anemonefish']);
    });
  });
}
