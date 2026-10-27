import 'package:discere/learning/model/deck_format.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _deckJson([Map<String, Object?> extra = const {}]) => {
  'name': 'Red Sea',
  'description': 'Fishes',
  'speciesNames': ['Pterois miles'],
  ...extra,
};

const _subdecks = [
  {
    'id': 'level-1',
    'name': 'Level 1',
    'speciesNames': ['Pterois miles'],
  },
];

void main() {
  group('DeckFormat.declaredIn', () {
    test('a deck without a version is version 1', () {
      final format = DeckFormat.declaredIn(_deckJson());

      expect(format, isA<ReadableDeckFormat>());
      expect((format as ReadableDeckFormat).version, 1);
    });

    test('an explicit null counts as no version', () {
      final format = DeckFormat.declaredIn(_deckJson({'formatVersion': null}));

      expect((format as ReadableDeckFormat).version, 1);
    });

    for (final version in [1, DeckFormat.supportedVersion]) {
      test('version $version is readable', () {
        final format = DeckFormat.declaredIn(
          _deckJson({'formatVersion': version}),
        );

        expect((format as ReadableDeckFormat).version, version);
      });
    }

    test('the version after the supported one is newer, not readable', () {
      final format = DeckFormat.declaredIn(
        _deckJson({'formatVersion': DeckFormat.supportedVersion + 1}),
      );

      expect(format, isA<NewerDeckFormat>());
      expect(
        (format as NewerDeckFormat).version,
        DeckFormat.supportedVersion + 1,
      );
    });

    for (final (label, version) in [
      ('a string', '2'),
      ('a JSON number with a fraction', 2.0),
      ('zero', 0),
      ('a negative number', -1),
    ]) {
      test('$label is a malformed version', () {
        expect(
          DeckFormat.declaredIn(_deckJson({'formatVersion': version})),
          isA<MalformedDeckFormat>(),
        );
      });
    }
  });

  group('DeckFormat.requiredVersion', () {
    test('a deck without subdecks needs version 1', () {
      expect(DeckFormat.requiredVersion(_deckJson()), 1);
    });

    test('a deck with subdecks needs version 2', () {
      expect(DeckFormat.requiredVersion(_deckJson({'subdecks': _subdecks})), 2);
    });

    test(
      'an empty subdeck list needs version 1: ignoring it loses nothing',
      () {
        expect(
          DeckFormat.requiredVersion(_deckJson({'subdecks': const []})),
          1,
        );
      },
    );

    test('the learning settings alone need version 1: an older app may '
        'ignore them', () {
      expect(
        DeckFormat.requiredVersion(
          _deckJson({
            'learningMode': 'genus',
            'nameType': 'scientificName',
            'reviewMode': 'multipleChoice',
          }),
        ),
        1,
      );
    });
  });

  group('DeckFormat.declare', () {
    test('declares version 2 for a deck with subdecks', () {
      final json = DeckFormat.declare(_deckJson({'subdecks': _subdecks}));

      expect(json['formatVersion'], 2);
      expect(json['subdecks'], _subdecks);
    });

    test(
      'declares nothing for version 1, which a missing field stands for',
      () {
        expect(DeckFormat.declare(_deckJson()), _deckJson());
      },
    );

    test('what it declares reads back as the same version', () {
      final json = DeckFormat.declare(_deckJson({'subdecks': _subdecks}));

      expect((DeckFormat.declaredIn(json) as ReadableDeckFormat).version, 2);
    });
  });
}
