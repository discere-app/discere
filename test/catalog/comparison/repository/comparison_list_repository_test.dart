import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/repository/comparison_list_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

final _monday = DateTime(2026, 11, 2, 9);
final _tuesday = DateTime(2026, 11, 3, 9);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ComparisonListRepository repository;

  setUp(() async {
    db = await openInMemoryUserDatabase();
    repository = ComparisonListRepository(database: db);
  });

  tearDown(() => db.close());

  /// Each list as (id, name, its species joined by commas) — a record of
  /// strings compares by value, a list inside it would not.
  Future<List<(String, String, String)>> lists() async => [
    for (final ComparisonList list in await repository.getLists())
      (list.id, list.name, list.speciesIds.join(',')),
  ];

  test(
    'creates a list with its species in the order they were passed',
    () async {
      await repository.createList(
        id: 'l1',
        name: 'Anemonefish',
        speciesIds: {'sp-c', 'sp-a', 'sp-b'},
        at: _monday,
      );

      expect(await lists(), [('l1', 'Anemonefish', 'sp-c,sp-a,sp-b')]);
    },
  );

  test('lists the newest list first', () async {
    await repository.createList(
      id: 'old',
      name: 'Old',
      speciesIds: const {},
      at: _monday,
    );
    await repository.createList(
      id: 'new',
      name: 'New',
      speciesIds: const {},
      at: _tuesday,
    );

    expect((await lists()).map((list) => list.$1), ['new', 'old']);
  });

  test('adds species after the ones already there, keeping a species already '
      'in the list once and in its place', () async {
    await repository.createList(
      id: 'l1',
      name: 'Rays',
      speciesIds: {'sp-a', 'sp-b'},
      at: _monday,
    );

    await repository.addSpecies('l1', {'sp-c', 'sp-a'});

    expect((await lists()).single.$3, 'sp-a,sp-b,sp-c');
    expect(
      await db.query('comparison_list_species', where: "species_id = 'sp-a'"),
      hasLength(1),
    );
  });

  test('removes one species and keeps a list left empty', () async {
    await repository.createList(
      id: 'l1',
      name: 'Rays',
      speciesIds: {'sp-a'},
      at: _monday,
    );

    await repository.removeSpecies('l1', 'sp-a');

    expect(await lists(), [('l1', 'Rays', '')]);
  });

  test('a removed species put back takes its old place, also among species '
      'added together', () async {
    await repository.createList(
      id: 'l1',
      name: 'Rays',
      speciesIds: {'sp-a', 'sp-b', 'sp-c'},
      at: _monday,
    );

    final removed = await repository.removeSpecies('l1', 'sp-b');
    expect((await lists()).single.$3, 'sp-a,sp-c');
    await repository.restoreSpecies(removed!);

    expect((await lists()).single.$3, 'sp-a,sp-b,sp-c');
  });

  test('removing a species the list does not hold answers nothing to put '
      'back; putting back into a deleted list does nothing', () async {
    await repository.createList(
      id: 'l1',
      name: 'Rays',
      speciesIds: {'sp-a'},
      at: _monday,
    );

    expect(await repository.removeSpecies('l1', 'sp-x'), isNull);

    final removed = await repository.removeSpecies('l1', 'sp-a');
    await repository.deleteList('l1');
    await repository.restoreSpecies(removed!);

    expect(await lists(), isEmpty);
    expect(await db.query('comparison_list_species'), isEmpty);
  });

  test('renames a list', () async {
    await repository.createList(
      id: 'l1',
      name: 'Rays',
      speciesIds: const {},
      at: _monday,
    );

    await repository.renameList('l1', 'Stingrays');

    expect((await lists()).single.$2, 'Stingrays');
  });

  test('deleting a list takes its species along and leaves other lists '
      'alone', () async {
    await repository.createList(
      id: 'l1',
      name: 'Rays',
      speciesIds: {'sp-a', 'sp-b'},
      at: _monday,
    );
    await repository.createList(
      id: 'l2',
      name: 'Sharks',
      speciesIds: {'sp-a'},
      at: _monday,
    );

    await repository.deleteList('l1');

    expect(await lists(), [('l2', 'Sharks', 'sp-a')]);
    expect(
      (await db.query('comparison_list_species')).map((r) => r['list_id']),
      ['l2'],
    );
  });
}
