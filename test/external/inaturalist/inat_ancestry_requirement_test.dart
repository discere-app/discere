import 'package:discere/external/inaturalist/inat_ancestry_requirement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('is met when the ancestry holds one id of every entry', () {
    const requirement = INatAncestryRequirement([
      {2, 5},
      {30},
    ]);

    expect(requirement.isMetBy([1, 5, 30, 31]), isTrue);
    expect(requirement.isMetBy([1, 2, 33]), isFalse);
    expect(requirement.isMetBy([1, 3, 30]), isFalse);
  });

  test('cannot be met without anything to check against', () {
    expect(const INatAncestryRequirement([]).canBeMet, isFalse);
    expect(const INatAncestryRequirement([]).isMetBy([1, 2]), isFalse);
    expect(
      const INatAncestryRequirement([
        {2},
        {},
      ]).canBeMet,
      isFalse,
    );
    expect(
      const INatAncestryRequirement([
        {2},
      ]).canBeMet,
      isTrue,
    );
  });
}
