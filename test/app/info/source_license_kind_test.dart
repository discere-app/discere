/// The licence keys come from the ETL and are not a closed set, so the
/// mapping has to stay forgiving without becoming wrong. Both halves of that
/// were a chain of if-statements inside a private widget method until the
/// page was split.
library;

import 'package:discere/app/info/source_license_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the two attribution-only spellings map to CC BY', () {
    expect(sourceLicenseKindFor('CC BY 4.0'), SourceLicenseKind.ccBy);
    expect(sourceLicenseKindFor('CC BY / CC0'), SourceLicenseKind.ccBy);
  });

  test('the exact non-commercial spelling maps to CC BY-NC', () {
    expect(
      sourceLicenseKindFor('CC BY-NC 4.0'),
      SourceLicenseKind.ccByNonCommercial,
    );
  });

  test('an unfamiliar key containing NC is still non-commercial', () {
    expect(
      sourceLicenseKindFor('CC BY-NC-SA 3.0'),
      SourceLicenseKind.ccByNonCommercial,
    );
  });

  test('the NC catch-all does not swallow the plain CC BY spellings', () {
    // 'CC BY / CC0' contains no NC, but the ordering matters the moment a
    // future key does — the specific spellings are checked first.
    expect(sourceLicenseKindFor('CC BY / CC0'), SourceLicenseKind.ccBy);
  });

  test('ARR maps to all-rights-reserved', () {
    expect(sourceLicenseKindFor('ARR'), SourceLicenseKind.allRightsReserved);
  });

  test('an unknown key is reported as such rather than guessed at', () {
    expect(sourceLicenseKindFor('MIT'), SourceLicenseKind.unknown);
    expect(sourceLicenseKindFor(''), SourceLicenseKind.unknown);
  });
}
