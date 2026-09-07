/// The QR capacity check exists because `QrValidator.validate` reports a
/// payload as valid that no QR version can actually hold — the real check
/// only runs when the image is built, which is too late to avoid throwing
/// mid-build. These tests pin that behaviour directly; the page-level tests
/// only see its consequences.
library;

import 'package:discere/learning/share/share_qr_capacity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('qrModuleCount', () {
    test('a short payload fits and reports a small grid', () {
      final modules = qrModuleCount('discere');
      expect(modules, isNotNull);
      expect(modules!, lessThan(denseQrModuleCountThreshold));
    });

    test('an empty payload still fits', () {
      expect(qrModuleCount(''), isNotNull);
    });

    test('a payload beyond every QR version reports null, not a throw', () {
      // Version 40 at error-correction level L holds roughly 2.9 KB.
      expect(qrModuleCount('x' * 5000), isNull);
    });

    test('a bigger payload never reports a smaller grid', () {
      final small = qrModuleCount('x' * 50)!;
      final large = qrModuleCount('x' * 500)!;
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
