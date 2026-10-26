import 'package:discere/learning/model/subdeck_structure.dart';
import 'package:discere/learning/repository/deck_merge_repository.dart';
import 'package:discere/learning/repository/subdeck_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/in_memory_user_database.dart';

const _old = 'deck-old';
const _new = 'deck-new';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late DeckMergeRepository repository;
  late SubdeckRepository subdecks;

  Future<void> card(
    String deckId,
    String speciesId, {
    int? lastReview,
    int? nextReview,
    double stability = 0,
    String learningMode = 'species',
  }) => db.insert('flashcard_stats', {
    'deck_id': deckId,
    'species_id': speciesId,
    'learning_mode': learningMode,
    'last_review_date': lastReview,
    'next_review_date': nextReview,
    'stability': stability,
  });

  Future<List<(String, String, double)>> cards() async {
    final rows = await db.query(
      'flashcard_stats',
      orderBy: 'deck_id, species_id, learning_mode',
    );
    return [
      for (final row in rows)
        (
          row['deck_id'] as String,
          '${row['species_id']}/${row['learning_mode']}',
          row['stability'] as double,
        ),
    ];
  }

  setUp(() async {
    db = await openInMemoryUserDatabase();
    repository = DeckMergeRepository(database: db);
    subdecks = SubdeckRepository(database: db);
    await db.insert('decks', {'id': _old, 'name': 'Old', 'sortOrder': 3});
    await db.insert('decks', {'id': _new, 'name': 'New', 'sortOrder': 7});
  });

  tearDown(() => db.close());

  test(
    'moves the cards of the species both decks hold and leaves the rest',
    () async {
      await card(_old, 'sp-shared', lastReview: 100, stability: 4.5);
      await card(_old, 'sp-shared', learningMode: 'genus', stability: 1.5);
      await card(_old, 'sp-only-old', lastReview: 100, stability: 2);
      // Never reviewed in the new deck: what the import created.
      await card(_new, 'sp-shared');
      await card(_new, 'sp-only-new');

      final moved = await repository.moveSharedProgress(
        fromDeckId: _old,
        toDeckId: _new,
      );

      expect(moved, {'sp-shared'});
      expect(await cards(), [
        ('deck-new', 'sp-only-new/species', 0.0),
        ('deck-new', 'sp-shared/genus', 1.5),
        ('deck-new', 'sp-shared/species', 4.5),
        ('deck-old', 'sp-only-old/species', 2.0),
      ]);
    },
  );

  test('a card both decks reviewed keeps the one reviewed last, whichever '
      'deck it comes from', () async {
    await card(_old, 'sp-a', lastReview: 200, stability: 9);
    await card(_new, 'sp-a', lastReview: 100, stability: 1);
    await card(_old, 'sp-b', lastReview: 100, stability: 1);
    await card(_new, 'sp-b', lastReview: 200, stability: 9);

    await repository.moveSharedProgress(fromDeckId: _old, toDeckId: _new);

    expect(await cards(), [
      ('deck-new', 'sp-a/species', 9.0),
      ('deck-new', 'sp-b/species', 9.0),
    ]);
  });

  test('moves the photo-gap acknowledgement, keeping one the target already '
      'has', () async {
    await card(_old, 'sp-a');
    await card(_new, 'sp-a');
    await card(_old, 'sp-b');
    await card(_new, 'sp-b');
    await db.insert('species_photo_gap_ack', {
      'deck_id': _old,
      'species_id': 'sp-a',
      'acknowledged_at': 11,
    });
    await db.insert('species_photo_gap_ack', {
      'deck_id': _old,
      'species_id': 'sp-b',
      'acknowledged_at': 12,
    });
    await db.insert('species_photo_gap_ack', {
      'deck_id': _new,
      'species_id': 'sp-b',
      'acknowledged_at': 99,
    });

    await repository.moveSharedProgress(fromDeckId: _old, toDeckId: _new);

    final acks = await db.query('species_photo_gap_ack', orderBy: 'species_id');
    expect(
      acks.map((r) => (r['deck_id'], r['species_id'], r['acknowledged_at'])),
      [(_new, 'sp-a', 11), (_new, 'sp-b', 99)],
    );
  });

  test('the species leaves its subdeck in the old deck, and its subdeck in '
      'the new one is switched on', () async {
    await card(_old, 'sp-a');
    await card(_new, 'sp-a');
    await card(_new, 'sp-c');
    await subdecks.writeStructure(
      _old,
      const SubdeckStructure(
        subdecks: [(id: 'o1', name: 'Old 1')],
        subdeckIdBySpeciesId: {'sp-a': 'o1'},
        subdeckIdByUnresolvedName: {},
      ),
    );
    await subdecks.writeStructure(
      _new,
      const SubdeckStructure(
        subdecks: [(id: 'n1', name: 'New 1'), (id: 'n2', name: 'New 2')],
        subdeckIdBySpeciesId: {'sp-a': 'n1', 'sp-c': 'n2'},
        subdeckIdByUnresolvedName: {},
      ),
    );
    await subdecks.setActiveSubdecks(_new, const {});

    await repository.moveSharedProgress(fromDeckId: _old, toDeckId: _new);

    expect(await subdecks.getSubdeckIdBySpeciesId(_old), isEmpty);
    expect((await subdecks.getSubdecks(_new)).map((s) => (s.id, s.isActive)), [
      ('n1', true),
      ('n2', false),
    ]);
  });

  test('a move that fails half way leaves both decks as they were', () async {
    await card(_old, 'sp-a', lastReview: 200, stability: 9);
    await card(_new, 'sp-a', lastReview: 100, stability: 1);
    await db.insert('species_photo_gap_ack', {
      'deck_id': _old,
      'species_id': 'sp-a',
      'acknowledged_at': 1,
    });
    await db.execute('''
      CREATE TRIGGER fail_ack_insert BEFORE INSERT ON species_photo_gap_ack
      WHEN NEW.deck_id = '$_new'
      BEGIN SELECT RAISE(ABORT, 'injected'); END
    ''');
    final before = await cards();

    await expectLater(
      repository.moveSharedProgress(fromDeckId: _old, toDeckId: _new),
      throwsA(isA<DatabaseException>()),
    );

    expect(await cards(), before);
    expect(await db.query('species_photo_gap_ack'), hasLength(1));
  });

  test('takes the position of another deck', () async {
    await repository.takePosition(_new, fromDeckId: _old);

    final rows = await db.query('decks', orderBy: 'id');
    expect(rows.map((r) => (r['id'], r['sortOrder'])), [(_new, 3), (_old, 3)]);
  });
}
