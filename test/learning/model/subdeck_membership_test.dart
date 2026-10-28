import 'package:discere/learning/model/subdeck_membership.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bySpecies = {'sp-a': 'l1', 'sp-b': 'l2', 'sp-c': 'l2'};

  test('counts the species of each subdeck among the given ones', () {
    expect(
      SubdeckMembership.of({'sp-a', 'sp-c', 'sp-x'}, bySpecies).speciesCounts,
      {'l1': 1, 'l2': 1},
    );
  });

  test('a species in no subdeck stands outside them', () {
    expect(
      SubdeckMembership.of({
        'sp-a',
        'sp-x',
      }, bySpecies).hasSpeciesOutsideSubdecks,
      isTrue,
    );
    expect(
      SubdeckMembership.of({
        'sp-a',
        'sp-b',
      }, bySpecies).hasSpeciesOutsideSubdecks,
      isFalse,
    );
  });

  test('the last subdeck on cannot be switched off while every species is '
      'in a subdeck', () {
    final allInSubdecks = SubdeckMembership.of({'sp-a', 'sp-b'}, bySpecies);
    expect(allInSubdecks.canSwitchOff('l1', {'l1'}), isFalse);
    expect(allInSubdecks.canSwitchOff('l1', {'l1', 'l2'}), isTrue);

    final oneOutside = SubdeckMembership.of({'sp-a', 'sp-x'}, bySpecies);
    expect(oneOutside.canSwitchOff('l1', {'l1'}), isTrue);
  });
}
