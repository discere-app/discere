/// The share page decides between a code, a dense-code warning and a
/// too-large notice from these two functions alone. These tests pin both
/// directly; the page-level tests only see their consequences.
library;

import 'package:discere/learning/share/share_qr_capacity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

void main() {
  group('encodeShareQr', () {
    test('a short payload fits and reports a small grid', () {
      final qrCode = encodeShareQr('discere');
      expect(qrCode, isNotNull);
      expect(qrCode!.moduleCount, lessThan(denseQrModuleCountThreshold));
    });

    test('an empty payload still fits', () {
      expect(encodeShareQr(''), isNotNull);
    });

    test('a payload beyond every QR version reports null, not a throw', () {
      // Version 40 at error-correction level low holds roughly 2.9 KB.
      expect(encodeShareQr('x' * 5000), isNull);
    });

    test('a large payload that fits also builds its module image', () {
      // A code the page accepts must not throw later when the module image
      // it paints is built from it.
      final qrCode = encodeShareQr('Ab0+' * 600);
      expect(qrCode, isNotNull);
      expect(() => QrImage(qrCode!), returnsNormally);
    });

    test('a bigger payload never reports a smaller grid', () {
      final small = encodeShareQr('x' * 50)!.moduleCount;
      final large = encodeShareQr('x' * 500)!.moduleCount;
      expect(large, greaterThan(small));
    });
  });

  group('isDenseQr', () {
    test('the threshold itself is not yet dense', () {
      expect(isDenseQr(denseQrModuleCountThreshold), isFalse);
    });

    test('one module past it is', () {
      expect(isDenseQr(denseQrModuleCountThreshold + 1), isTrue);
    });
  });
}
