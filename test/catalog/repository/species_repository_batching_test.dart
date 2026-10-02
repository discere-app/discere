import 'dart:io';
import 'dart:math';

import 'package:discere/catalog/repository/species_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Counts the statements a repository sends, by standing between it and a real
/// database rather than replacing one.
///
/// Everything still runs against the committed fixture, so the rows a query
/// returns are the rows the real schema returns — this only records how many
/// queries there were.
class _CountingDatabase extends Fake implements Database {
  _CountingDatabase(this._delegate);

  final Database _delegate;
  int statements = 0;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    statements++;
    return _delegate.rawQuery(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    statements++;
    return _delegate.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }
}

/// Guards that loading several species costs a fixed number of statements
/// rather than one set per species (#229 — a review session resolved its due
/// cards one at a time, so the time to the first card grew with how much was
/// due).
///
/// `species_media_service_test.dart` guards the service above this by counting
/// its calls to the repository. That cannot see inside `getSpecies`, which could
/// keep its signature and still issue a statement per id — losing the chunked
/// `IN`, say — while the service-level count stays at one call. So this test
/// counts statements instead of calls.
///
/// Counted, not timed. A timing comparison was the obvious first idea and does
/// not work: with the chunk size dropped to one, `getSpecies` still bundles its
/// supplementary loads and stays comfortably faster than the per-id path, so a
/// time-based assertion sails straight past exactly the regression it is meant
/// to catch. Statement counts see it, need no large database, and cannot flake
/// on a loaded machine.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database referenceDb;
  late Database userDb;
  late _CountingDatabase countingDb;
  late SpeciesRepository repository;
  late List<String> fixtureSpeciesIds;

  setUp(() async {
    final suffix =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(10000)}';
    final referencePath = join(
      Directory.systemTemp.path,
      'discere_batching_reference_$suffix.db',
    );
    final userPath = join(
      Directory.systemTemp.path,
      'discere_batching_user_$suffix.db',
    );
    await File(referencePath).writeAsBytes(
      await File('test/fixtures/discere_reference_test.db').readAsBytes(),
      flush: true,
    );

    referenceDb = await openDatabase(referencePath);
    userDb = await openDatabase(userPath);
    await userDb.execute('''
      CREATE TABLE runtime_common_names (
        entity_key TEXT NOT NULL, entity_type TEXT NOT NULL,
        language_code TEXT NOT NULL, name TEXT NOT NULL, position INTEGER,
        place_id INTEGER, place_position INTEGER, fetched_at INTEGER NOT NULL,
        PRIMARY KEY (entity_key, language_code, name, place_id))
    ''');

    final rows = await referenceDb.query(
      'species',
      columns: ['id'],
      where: 'genus IS NOT NULL',
      orderBy: 'id',
    );
    fixtureSpeciesIds = rows.map((row) => row['id'] as String).toList();

    countingDb = _CountingDatabase(referenceDb);
    repository = SpeciesRepository(
      database: countingDb,
      userDatabase: userDb,
    );

    addTearDown(() async {
      await referenceDb.close();
      await userDb.close();
      for (final path in [referencePath, userPath]) {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      }
    });
  });

  test('loads many species with the same statements as a few', () async {
    final few = fixtureSpeciesIds.take(3).toSet();
    final many = fixtureSpeciesIds.toSet();
    expect(
      many.length,
      greaterThan(few.length * 3),
      reason: 'the fixture must hold enough species for the two to differ',
    );

    countingDb.statements = 0;
    final fewResult = await repository.getSpecies(few);
    final statementsForFew = countingDb.statements;

    countingDb.statements = 0;
    final manyResult = await repository.getSpecies(many);
    final statementsForMany = countingDb.statements;

    expect(fewResult, hasLength(few.length));
    expect(manyResult, hasLength(many.length));
    expect(
      statementsForMany,
      statementsForFew,
      reason:
          'loading ${many.length} species took $statementsForMany statements '
          'against $statementsForFew for ${few.length} — the load is no longer '
          'batched',
    );
  });

  test('loads the whole fixture in a handful of statements', () async {
    countingDb.statements = 0;
    await repository.getSpecies(fixtureSpeciesIds.toSet());

    // Seven: the species rows, the lookup-table probe, and the five bulk
    // supplementary loads (pictures, traits, native regions, reference common
    // names, imported classification names). A per-species load multiplies all
    // of them by the number of species.
    expect(
      countingDb.statements,
      lessThanOrEqualTo(8),
      reason:
          'loading the whole fixture took ${countingDb.statements} statements; '
          'a batched load needs a handful regardless of how many species it is '
          'asked for',
    );
  });

  test('getSpeciesById is the single-species path, not what a list uses', () async {
    countingDb.statements = 0;
    await repository.getSpeciesById(fixtureSpeciesIds.first);
    final perSpecies = countingDb.statements;

    countingDb.statements = 0;
    await repository.getSpecies(fixtureSpeciesIds.toSet());
    final batched = countingDb.statements;

    // Not a performance claim, a shape claim: one species costs about what the
    // whole fixture costs, which is why resolving a list one species at a time
    // multiplies the work by the length of the list.
    expect(perSpecies, greaterThan(1));
    expect(batched, lessThanOrEqualTo(perSpecies + 2));
  });
}
