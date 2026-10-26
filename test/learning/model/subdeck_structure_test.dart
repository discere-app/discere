import 'package:discere/learning/model/create_subdeck.dart';
import 'package:discere/learning/model/subdeck_structure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('puts each resolved species into its subdeck and keeps the subdeck '
      'of each unresolved name', () {
    final structure = SubdeckStructure.resolve(
      const [
        CreateSubdeck(id: 'l1', name: 'Level 1', speciesNames: {'Aa aa'}),
        CreateSubdeck(
          id: 'l2',
          name: 'Level 2',
          speciesNames: {'Bb bb', 'Zz unknown'},
        ),
      ],
      {'Aa aa': 'sp-a', 'Bb bb': 'sp-b'},
    );

    expect(structure.subdecks, [
      (id: 'l1', name: 'Level 1'),
      (id: 'l2', name: 'Level 2'),
    ]);
    expect(structure.subdeckIdBySpeciesId, {'sp-a': 'l1', 'sp-b': 'l2'});
    expect(structure.subdeckIdByUnresolvedName, {'Zz unknown': 'l2'});
  });

  test('two names of one species in different subdecks put it in the '
      'first', () {
    final structure = SubdeckStructure.resolve(
      const [
        CreateSubdeck(id: 'l1', name: 'Level 1', speciesNames: {'Aa aa'}),
        CreateSubdeck(id: 'l2', name: 'Level 2', speciesNames: {'Aa synonym'}),
      ],
      {'Aa aa': 'sp-a', 'Aa synonym': 'sp-a'},
    );

    expect(structure.subdeckIdBySpeciesId, {'sp-a': 'l1'});
  });

  test('a name not resolved yet that two subdecks list waits for the '
      'first', () {
    final structure = SubdeckStructure.resolve(
      const [
        CreateSubdeck(id: 'l1', name: 'Level 1', speciesNames: {'Zz unknown'}),
        CreateSubdeck(id: 'l3', name: 'Level 3', speciesNames: {'Zz unknown'}),
      ],
      const {},
    );

    expect(structure.subdeckIdByUnresolvedName, {'Zz unknown': 'l1'});
  });

  test('a deck without subdecks resolves to none', () {
    expect(SubdeckStructure.resolve(null, {'Aa aa': 'sp-a'}).subdecks, isEmpty);
  });

  test('restrictedTo drops species outside the deck only', () {
    final structure = SubdeckStructure.resolve(
      const [
        CreateSubdeck(
          id: 'l1',
          name: 'Level 1',
          speciesNames: {'Aa aa', 'Bb bb', 'Zz unknown'},
        ),
      ],
      {'Aa aa': 'sp-a', 'Bb bb': 'sp-b'},
    ).restrictedTo({'sp-a'});

    expect(structure.subdeckIdBySpeciesId, {'sp-a': 'l1'});
    expect(structure.subdeckIdByUnresolvedName, {'Zz unknown': 'l1'});
  });
}
