import 'dart:io';
import 'dart:math';

import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers [SpeciesRepository.getSpecies], the batch/multi-id sibling of
/// getSpeciesById. That single-id path is exercised extensively elsewhere
/// (species_repository_common_names_test.dart); this file focuses on what's
/// specific to batching multiple species in one call: bulk-loaded
/// supplementary data (pictures, traits, native regions, common names) must
/// attach to the right species and not leak across rows.
Future<
  (
    Database referenceDb,
    Database userDb,
    String referenceDbPath,
    String userDbPath,
  )
>
initializeDatabases() async {
  final tempDir = Directory.systemTemp;
  final suffix =
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  final referenceDbPath = join(tempDir.path, 'test_reference_$suffix.db');
  final userDbPath = join(tempDir.path, 'test_user_$suffix.db');

  // Kuratierte Test-Fixture (kleine Untermenge der echten Referenz-DB,
  // siehe etl/scripts/build_test_fixture.sh).
  final bytes = await File(
    'test/fixtures/discere_reference_test.db',
  ).readAsBytes();
  await File(referenceDbPath).writeAsBytes(bytes, flush: true);

  final referenceDb = await openDatabase(referenceDbPath, readOnly: false);
  final userDb = await openDatabase(userDbPath);
  await userDb.execute('''
    CREATE TABLE runtime_common_names (
      entity_key     TEXT NOT NULL,
      entity_type    TEXT NOT NULL,
      language_code  TEXT NOT NULL,
      name           TEXT NOT NULL,
      position       INTEGER,
      place_id       INTEGER,
      place_position INTEGER,
      fetched_at     INTEGER NOT NULL,
      PRIMARY KEY (entity_key, language_code, name, place_id)
    )
  ''');

  return (referenceDb, userDb, referenceDbPath, userDbPath);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database referenceDb;
  late Database userDb;
  late String referenceDbPath;
  late String userDbPath;
  late SpeciesRepository repository;

  setUp(() async {
    final dbs = await initializeDatabases();
    referenceDb = dbs.$1;
    userDb = dbs.$2;
    referenceDbPath = dbs.$3;
    userDbPath = dbs.$4;
    repository = SpeciesRepository(database: referenceDb, userDatabase: userDb);
  });

  tearDown(() async {
    await referenceDb.close();
    await userDb.close();
    final referenceFile = File(referenceDbPath);
    if (await referenceFile.exists()) {
      await referenceFile.delete();
    }
    final userFile = File(userDbPath);
    if (await userFile.exists()) {
      await userFile.delete();
    }
  });

  test('getSpecies returns an empty set for an empty id set', () async {
    final result = await repository.getSpecies({});
    expect(result, isEmpty);
  });

  test('getSpecies skips unknown ids and returns only the matches found', () async {
    final row = (await referenceDb.rawQuery('''
      SELECT s.id
      FROM species s
      JOIN genera g ON s.genus = g.id
      JOIN families f ON g.family = f.id
      JOIN orders o ON f."order" = o.id
      JOIN classes c ON o.class = c.id
      WHERE s.status = 'active'
      LIMIT 1
    ''')).first;
    final knownId = row['id'] as String;

    final result = await repository.getSpecies({knownId, 'does-not-exist'});

    expect(result.map((species) => species.id), [knownId]);
  });

  test(
    'getSpecies batch-loads several species without cross-attributing '
    'supplementary data between them',
    () async {
      final rows = await referenceDb.rawQuery('''
        SELECT DISTINCT s.id
        FROM species s
        JOIN genera g ON s.genus = g.id
        JOIN families f ON g.family = f.id
        JOIN orders o ON f."order" = o.id
        JOIN classes c ON o.class = c.id
        WHERE s.status = 'active'
        LIMIT 5
      ''');
      final ids = rows.map((row) => row['id'] as String).toSet();
      expect(ids.length, greaterThanOrEqualTo(2));

      // Give each species a distinguishing runtime common name so a mixup
      // during bulk-loading would be observable.
      var position = 0;
      for (final id in ids) {
        await userDb.insert('runtime_common_names', {
          'entity_key': 'species:$id',
          'entity_type': 'species',
          'language_code': 'en',
          'name': 'Runtime name for $id',
          'position': position++,
          'place_id': null,
          'place_position': null,
          'fetched_at': DateTime.now().millisecondsSinceEpoch,
        });
      }

      final individually = <String, dynamic>{};
      for (final id in ids) {
        individually[id] = (await repository.getSpeciesById(id))!;
      }

      final batch = await repository.getSpecies(ids);

      expect(batch.map((species) => species.id).toSet(), ids);
      for (final species in batch) {
        final expected = individually[species.id];
        expect(
          species.commonNames,
          expected.commonNames,
          reason: 'commonNames mismatch for ${species.id}',
        );
        // Each species got its own runtime common name inserted above; a
        // batch-loading mixup would attach the wrong species' name here.
        expect(
          species.commonNames[Language.en] ?? const [],
          contains('Runtime name for ${species.id}'),
          reason: 'runtime common name mixup for ${species.id}',
        );
        expect(
          species.pictures.map((picture) => picture.id).toList(),
          expected.pictures.map((picture) => picture.id).toList(),
          reason: 'pictures mismatch for ${species.id}',
        );
        expect(
          species.traits,
          expected.traits,
          reason: 'traits mismatch for ${species.id}',
        );
        expect(
          species.nativeRegions.length,
          expected.nativeRegions.length,
          reason: 'nativeRegions mismatch for ${species.id}',
        );
        expect(
          species.classification.genusScientificName,
          expected.classification.genusScientificName,
          reason: 'classification mismatch for ${species.id}',
        );
      }
    },
  );
}
