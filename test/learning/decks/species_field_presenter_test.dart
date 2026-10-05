import 'package:discere/learning/decks/species_field_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const presenter = SpeciesFieldPresenter();

  group('lines', () {
    test('trims, skips blank lines and keeps the order', () {
      expect(
        presenter.lines('  Sphyrna mokarran \n\n   \nCarcharodon carcharias\n'),
        ['Sphyrna mokarran', 'Carcharodon carcharias'],
      );
    });

    test('drops a name repeated with other case, spacing or author', () {
      expect(
        presenter.lines(
          'Carcharodon carcharias\n'
          'carcharodon   CARCHARIAS\n'
          'Carcharodon carcharias (Linnaeus, 1758)\n'
          'Amphiprion\n'
          'amphiprion',
        ),
        ['Carcharodon carcharias', 'Amphiprion'],
      );
    });
  });

  test('speciesNames keeps only lines a lookup can match', () {
    expect(
      presenter.speciesNames([
        'Carcharodon carcharias (Linnaeus, 1758)',
        'Amphiprion',
        '"Sphyrna mokarran",',
        'Polygonia c-album',
      ]),
      ['Carcharodon carcharias (Linnaeus, 1758)', 'Polygonia c-album'],
    );
  });

  test('check sorts lines into found, not found locally and no name', () {
    final check = presenter.check(
      [
        'Carcharodon carcharias (Linnaeus, 1758)',
        'Sphyrna mokarran',
        'Amphiprion ocelaris',
        'Amphiprion',
      ],
      {
        'Carcharodon carcharias (Linnaeus, 1758)': 'species-1',
        'Sphyrna mokarran': 'species-2',
      },
    );

    expect(check.foundCount, 2);
    expect(check.notFoundLocally, ['Amphiprion ocelaris']);
    expect(check.notSpeciesNames, ['Amphiprion']);
  });

  group('abbreviate', () {
    test('shows a short list whole', () {
      final (:shown, :hiddenCount) = presenter.abbreviate(['a', 'b', 'c']);

      expect(shown, ['a', 'b', 'c']);
      expect(hiddenCount, 0);
    });

    test('cuts a long list and counts the rest', () {
      final (:shown, :hiddenCount) = presenter.abbreviate([
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);

      expect(shown, ['a', 'b', 'c']);
      expect(hiddenCount, 2);
    });
  });
}
