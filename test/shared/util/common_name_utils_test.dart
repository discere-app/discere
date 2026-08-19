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

  group('resolveCommonNamesResolution', () {
    test('reports no fallback when the selected language has names', () {
      final resolution = resolveCommonNamesResolution(const {
        Language.de: ['Falscher Clownfisch'],
        Language.en: ['Clown anemonefish'],
      }, Language.de);

      expect(resolution.names, ['Falscher Clownfisch']);
      expect(resolution.isEnglishFallback, isFalse);
    });

    test('reports a fallback when falling back to English', () {
      final resolution = resolveCommonNamesResolution(const {
        Language.en: ['Clown anemonefish'],
      }, Language.de);

      expect(resolution.names, ['Clown anemonefish']);
      expect(resolution.isEnglishFallback, isTrue);
    });

    test('reports no fallback when nothing is available at all', () {
      final resolution = resolveCommonNamesResolution(const {}, Language.de);

      expect(resolution.names, isEmpty);
      expect(resolution.isEnglishFallback, isFalse);
    });

    test('reports no fallback when the selected language already is '
        'English', () {
      final resolution = resolveCommonNamesResolution(const {
        Language.en: ['Clown anemonefish'],
      }, Language.en);

      expect(resolution.names, ['Clown anemonefish']);
      expect(resolution.isEnglishFallback, isFalse);
    });
  });
}
