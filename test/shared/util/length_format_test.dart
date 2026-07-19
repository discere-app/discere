import 'package:discere/shared/util/length_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatLengthCm', () {
    test('returns null for null input', () {
      expect(formatLengthCm(null), isNull);
    });

    test('formats sub-centimeter lengths in mm', () {
      expect(formatLengthCm(0.5), '5 mm');
    });

    test('formats lengths below 1 m in cm', () {
      expect(formatLengthCm(70), '70 cm');
      expect(formatLengthCm(99.9), '99.9 cm');
    });

    test('formats lengths from 1 m upward in m', () {
      expect(formatLengthCm(100), '1 m');
      expect(formatLengthCm(1700), '17 m');
      expect(formatLengthCm(140), '1.4 m');
    });
  });
}
