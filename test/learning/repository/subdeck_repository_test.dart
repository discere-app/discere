import 'package:discere/learning/model/subdeck_edit.dart';
import 'package:discere/learning/model/subdeck_structure.dart';
import 'package:discere/learning/repository/subdeck_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/in_memory_user_database.dart';

const _deckId = 'deck-1';

SubdeckStructure _levels({
  Map<String, String> bySpecies = const {'sp-a': 'l1', 'sp-b': 'l2'},
  Map<String, String> byName = const {},
  List<SubdeckHeading> subdecks = const [
    (id: 'l1', name: 'Level 1'),
    (id: 'l2', name: 'Level 2'),
  ],
}) => SubdeckStructure(
  subdecks: subdecks,
  subdeckIdBySpeciesId: bySpecies,
  subdeckIdByUnresolvedName: byName,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SubdeckRepository repository;

  setUp(() async {
    db = await openInMemoryUserDatabase();
    repository = SubdeckRepository(database: db);
    await db.insert('decks', {'id': _deckId, 'name': 'Red Sea'});
  });

  tearDown(() => db.close());

  test(
    'writes and reads a structure, subdecks in order',
    () async {
      await repository.writeStructure(_deckId, _levels());

      final subdecks = await repository.getSubdecks(_deckId);
      expect(
        subdecks.map((s) => (s.id, s.name, s.sortOrder, s.isActive)),
        [('l1', 'Level 1', 0, true), ('l2', 'Level 2', 1, true)],
      );
      expect(await repository.getSubdeckIdBySpeciesId(_deckId), {
        'sp-a': 'l1',
        'sp-b': 'l2',
      });
    },
  );

  test('rewriting keeps a subdeck switched off, renames it, adds new ones '
      'active and drops the missing one with its species', () async {
    await repository.writeStructure(_deckId, _levels());
    await repository.setActiveSubdecks(_deckId, {'l2'});

    await repository.writeStructure(
      _deckId,
      _levels(
        subdecks: const [
          (id: 'l1', name: 'Beginner'),
          (id: 'l3', name: 'Level 3'),
        ],
        bySpecies: const {'sp-a': 'l3', 'sp-c': 'l1'},
      ),
    );

    final subdecks = await repository.getSubdecks(_deckId);
    expect(subdecks.map((s) => (s.id, s.name, s.isActive)), [
      ('l1', 'Beginner', false),
      ('l3', 'Level 3', true),
    ]);
    expect(await repository.getSubdeckIdBySpeciesId(_deckId), {
      'sp-a': 'l3',
      'sp-c': 'l1',
    });
  });

  test('species of switched-off subdecks, per deck and across decks', () async {
    await db.insert('decks', {'id': 'deck-2', 'name': 'Alps'});
    await repository.writeStructure(_deckId, _levels());
    await repository.writeStructure('deck-2', _levels());
    await repository.setActiveSubdecks(_deckId, {'l1'});

    expect(await repository.getSpeciesIdsInInactiveSubdecks(_deckId), {'sp-b'});
    expect(await repository.getSpeciesIdsInInactiveSubdecks('deck-2'), isEmpty);
    expect(await repository.getSpeciesIdsInInactiveSubdecksByDeckId(), {
      _deckId: {'sp-b'},
    });
  });

  test('a resolved name lands in the subdeck it was listed in, once', () async {
    await repository.writeStructure(
      _deckId,
      _levels(byName: const {'Zz unknown': 'l2'}),
    );

    await repository.assignResolvedName(_deckId, 'Zz unknown', 'sp-z');
    await repository.assignResolvedName(_deckId, 'Zz unknown', 'sp-other');

    final assignment = await repository.getSubdeckIdBySpeciesId(_deckId);
    expect(assignment['sp-z'], 'l2');
    expect(assignment.containsKey('sp-other'), isFalse);
  });

  test('a resolved name for a species already in a subdeck leaves it '
      'there', () async {
    await repository.writeStructure(
      _deckId,
      _levels(byName: const {'Aa synonym': 'l2'}),
    );

    await repository.assignResolvedName(_deckId, 'Aa synonym', 'sp-a');

    expect((await repository.getSubdeckIdBySpeciesId(_deckId))['sp-a'], 'l1');
  });

  test('removeSpecies takes species out of their subdeck', () async {
    await repository.writeStructure(_deckId, _levels());

    await repository.removeSpecies(_deckId, {'sp-a'});

    expect(await repository.getSubdeckIdBySpeciesId(_deckId), {'sp-b': 'l2'});
  });

  group('applyEdit', () {
    const levels = [
      (id: 'l1', name: 'Level 1'),
      (id: 'l2', name: 'Level 2'),
    ];

    Future<Map<String, String>> unresolvedNames() async => {
      for (final row in await db.query('deck_subdeck_unresolved_names'))
        row['name'] as String: row['subdeck_id'] as String,
    };

    test('leaves waiting names, unmoved species and switches alone', () async {
      // sp-unresolved stands for a species the edit page cannot show.
      await repository.writeStructure(
        _deckId,
        _levels(
          bySpecies: const {
            'sp-a': 'l1',
            'sp-b': 'l2',
            'sp-unresolved': 'l1',
          },
          byName: const {'Zz waiting': 'l1'},
        ),
      );
      await repository.setActiveSubdecks(_deckId, {'l2'});

      await repository.applyEdit(
        _deckId,
        const SubdeckEdit(subdecks: levels, moves: {'sp-a': 'l2'}),
      );

      expect(await repository.getSubdeckIdBySpeciesId(_deckId), {
        'sp-a': 'l2',
        'sp-b': 'l2',
        'sp-unresolved': 'l1',
      });
      expect(await unresolvedNames(), {'Zz waiting': 'l1'});
      expect((await repository.getSubdecks(_deckId)).map((s) => s.isActive), [
        false,
        true,
      ]);
    });

    test('names, orders and adds subdecks, a new one on', () async {
      await repository.writeStructure(_deckId, _levels());
      await repository.setActiveSubdecks(_deckId, {'l1'});

      await repository.applyEdit(
        _deckId,
        const SubdeckEdit(
          subdecks: [
            (id: 'new', name: 'New'),
            (id: 'l2', name: 'Second'),
            (id: 'l1', name: 'Level 1'),
          ],
          moves: {},
        ),
      );

      expect(
        (await repository.getSubdecks(
          _deckId,
        )).map((s) => (s.id, s.name, s.sortOrder, s.isActive)),
        [
          ('new', 'New', 0, true),
          ('l2', 'Second', 1, false),
          ('l1', 'Level 1', 2, true),
        ],
      );
    });

    test('moves into a subdeck the same edit adds, and into none', () async {
      await repository.writeStructure(_deckId, _levels());

      await repository.applyEdit(
        _deckId,
        const SubdeckEdit(
          subdecks: [...levels, (id: 'new', name: 'New')],
          moves: {'sp-a': 'new', 'sp-b': null, 'sp-c': 'new'},
        ),
      );

      expect(await repository.getSubdeckIdBySpeciesId(_deckId), {
        'sp-a': 'new',
        'sp-c': 'new',
      });
    });

    test('a deleted subdeck takes its assignments and waiting names', () async {
      await repository.writeStructure(
        _deckId,
        _levels(byName: const {'Zz gone': 'l1', 'Zz kept': 'l2'}),
      );

      await repository.applyEdit(
        _deckId,
        const SubdeckEdit(subdecks: [(id: 'l2', name: 'Level 2')], moves: {}),
      );

      expect(await repository.getSubdeckIdBySpeciesId(_deckId), {'sp-b': 'l2'});
      expect(await unresolvedNames(), {'Zz kept': 'l2'});
    });

    test('deleting the last subdeck works', () async {
      await repository.writeStructure(_deckId, _levels());

      await repository.applyEdit(
        _deckId,
        const SubdeckEdit(subdecks: [], moves: {}),
      );

      expect(await repository.getSubdecks(_deckId), isEmpty);
    });
  });

  group('customization mark', () {
    const edit = SubdeckEdit(subdecks: [(id: 'l1', name: 'L')], moves: {});

    test('a deck starts without', () async {
      await repository.writeStructure(_deckId, _levels());

      expect(await repository.isCustomized(_deckId), isFalse);
    });

    test('an edit sets it, for that deck alone, and twice does no harm', () async {
      await db.insert('decks', {'id': 'deck-2', 'name': 'Alps'});

      await repository.applyEdit(_deckId, edit);
      await repository.applyEdit(_deckId, edit);

      expect(await repository.isCustomized(_deckId), isTrue);
      expect(await repository.isCustomized('deck-2'), isFalse);
    });

    test('switching subdecks does not set it', () async {
      await repository.writeStructure(_deckId, _levels());

      await repository.setActiveSubdecks(_deckId, {'l1'});

      expect(await repository.isCustomized(_deckId), isFalse);
    });

    test('taking on a whole structure clears it', () async {
      await repository.applyEdit(_deckId, edit);

      await repository.writeStructure(_deckId, _levels());

      expect(await repository.isCustomized(_deckId), isFalse);
    });

    test('deleting the deck removes it', () async {
      await repository.applyEdit(_deckId, edit);

      await db.delete('decks', where: 'id = ?', whereArgs: [_deckId]);

      expect(await db.query('deck_subdeck_customizations'), isEmpty);
    });
  });

  group('addToExistingSubdecks', () {
    test('places what is new, in existing subdecks only', () async {
      await repository.writeStructure(_deckId, _levels());

      await repository.addToExistingSubdecks(
        _deckId,
        _levels(
          bySpecies: const {'sp-new': 'l2', 'sp-elsewhere': 'not-here'},
          byName: const {'Zz new': 'l1', 'Zz elsewhere': 'not-here'},
        ),
      );

      final assignment = await repository.getSubdeckIdBySpeciesId(_deckId);
      expect(assignment['sp-new'], 'l2');
      expect(assignment.containsKey('sp-elsewhere'), isFalse);
      expect(await db.query('deck_subdeck_unresolved_names'), [
        {'deck_id': _deckId, 'name': 'Zz new', 'subdeck_id': 'l1'},
      ]);
      expect((await repository.getSubdecks(_deckId)).map((s) => s.id), [
        'l1',
        'l2',
      ]);
    });

    test('overwrites nothing', () async {
      await repository.writeStructure(
        _deckId,
        _levels(byName: const {'Zz waiting': 'l1'}),
      );

      await repository.addToExistingSubdecks(
        _deckId,
        _levels(
          bySpecies: const {'sp-a': 'l2'},
          byName: const {'Zz waiting': 'l2'},
        ),
      );

      expect((await repository.getSubdeckIdBySpeciesId(_deckId))['sp-a'], 'l1');
      expect(
        (await db.query('deck_subdeck_unresolved_names')).single['subdeck_id'],
        'l1',
      );
    });
  });

  test('deleting the deck deletes its subdecks, species and names', () async {
    await repository.writeStructure(
      _deckId,
      _levels(byName: const {'Zz unknown': 'l2'}),
    );

    await db.delete('decks', where: 'id = ?', whereArgs: [_deckId]);

    for (final table in [
      'deck_subdecks',
      'deck_subdeck_species',
      'deck_subdeck_unresolved_names',
    ]) {
      expect(await db.query(table), isEmpty, reason: table);
    }
  });
}
