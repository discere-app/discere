import 'package:discere/catalog/model/iucn_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IucnStatus.fromRaw', () {
    test('parses all known codes case-insensitively', () {
      expect(IucnStatus.fromRaw('EX'), IucnStatus.extinct);
      expect(IucnStatus.fromRaw('ew'), IucnStatus.extinctInTheWild);
      expect(IucnStatus.fromRaw('Cr'), IucnStatus.criticallyEndangered);
      expect(IucnStatus.fromRaw('en'), IucnStatus.endangered);
      expect(IucnStatus.fromRaw('vu'), IucnStatus.vulnerable);
      expect(IucnStatus.fromRaw('nt'), IucnStatus.nearThreatened);
      expect(IucnStatus.fromRaw('lc'), IucnStatus.leastConcern);
      expect(IucnStatus.fromRaw('dd'), IucnStatus.dataDeficient);
      expect(IucnStatus.fromRaw('ne'), IucnStatus.notEvaluated);
    });

    test('returns null for an unknown code', () {
      expect(IucnStatus.fromRaw('sc'), isNull);
      expect(IucnStatus.fromRaw(''), isNull);
    });
  });

  group('IucnStatus.isOnThreatSpectrum', () {
    test('is true for the seven threat-scale categories', () {
      for (final status in IucnStatus.threatSpectrum) {
        expect(status.isOnThreatSpectrum, isTrue);
      }
    });

    test('is false for data deficient and not evaluated', () {
      expect(IucnStatus.dataDeficient.isOnThreatSpectrum, isFalse);
      expect(IucnStatus.notEvaluated.isOnThreatSpectrum, isFalse);
    });
  });

  test('code returns the two-letter IUCN abbreviation', () {
    expect(IucnStatus.vulnerable.code, 'VU');
    expect(IucnStatus.leastConcern.code, 'LC');
  });
}
