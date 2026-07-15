import 'package:discere/enrichment/util/ordered_unique_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('orderedUniqueStrings', () {
    test('preserves first-seen order and drops later duplicates', () {
      expect(orderedUniqueStrings(['b', 'a', 'b', 'c', 'a']), ['b', 'a', 'c']);
    });

    test('trims whitespace before comparing and returning', () {
      expect(orderedUniqueStrings([' a', 'a ', ' a ']), ['a']);
    });

    test('drops empty and whitespace-only entries', () {
      expect(orderedUniqueStrings(['a', '', '  ', 'b']), ['a', 'b']);
    });

    test('returns an empty list for empty input', () {
      expect(orderedUniqueStrings(const []), isEmpty);
    });
  });
}
