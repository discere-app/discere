import 'dart:io';
import 'dart:math';

import 'package:discere/model/language.dart';
import 'package:discere/persistence/species_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  final data = await rootBundle.load('assets/database/discere_reference.db');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  await File(referenceDbPath).writeAsBytes(bytes, flush: true);

  final referenceDb = await openDatabase(referenceDbPath, readOnly: false);
  final userDb = await openDatabase(userDbPath);
  await userDb.execute('''
    CREATE TABLE inat_common_names (
      species_id     TEXT NOT NULL,
      language_code  TEXT NOT NULL,
      names          TEXT NOT NULL,
      fetched_at     INTEGER NOT NULL,
      PRIMARY KEY (species_id, language_code)
    )
  ''');
  await userDb.execute('''
    CREATE TABLE inat_taxonomy_common_names (
      entity_key     TEXT NOT NULL,
      language_code  TEXT NOT NULL,
      names          TEXT NOT NULL,
      fetched_at     INTEGER NOT NULL,
      PRIMARY KEY (entity_key, language_code)
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

  test(
    'maps fr/es common names from the reference DB in main species reads',
    () async {
      final row = (await referenceDb.rawQuery('''
      SELECT id, common_name_fr, common_name_es
      FROM species
      WHERE TRIM(COALESCE(common_name_fr, '')) != ''
         OR TRIM(COALESCE(common_name_es, '')) != ''
      LIMIT 1
    ''')).first;

      final species = await repository.getSpeciesById(row['id'] as String);

      expect(species, isNotNull);
      expect(
        (species!.commonNames[Language.fr] ?? '').isNotEmpty ||
            (species.commonNames[Language.es] ?? '').isNotEmpty,
        isTrue,
      );
    },
  );

  test(
    'merges persisted iNat common names without duplicating normalized matches and keeps iNat first',
    () async {
      final row = (await referenceDb.rawQuery('''
      SELECT id, common_name_en
      FROM species
      WHERE TRIM(COALESCE(common_name_en, '')) != ''
      LIMIT 1
    ''')).first;
      final speciesId = row['id'] as String;
      final existingEnglish = row['common_name_en'] as String;
      final firstExistingName = existingEnglish.split(';').first.trim();

      await userDb.insert('inat_common_names', {
        'species_id': speciesId,
        'language_code': 'en',
        'names': 'Lagoon clownfish;  ${firstExistingName.toUpperCase()}  ',
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      });

      final species = await repository.getSpeciesById(speciesId);

      expect(species, isNotNull);
      final englishNames = (species!.commonNames[Language.en] ?? '').split(';');
      expect(
        englishNames
            .where(
              (name) =>
                  name.trim().toLowerCase() == firstExistingName.toLowerCase(),
            )
            .length,
        1,
      );
      expect(
        englishNames.map((name) => name.trim()),
        contains('Lagoon clownfish'),
      );
      expect(englishNames.first.trim(), 'Lagoon clownfish');
    },
  );

  test(
    'merges persisted iNat taxonomy names into classification with iNat first',
    () async {
      final species = await repository.getSpeciesById(
        (await referenceDb.rawQuery(
              '''
              SELECT s.id
              FROM species s
              JOIN genera g ON s.genus = g.id
              JOIN families f ON g.family = f.id
              JOIN orders o ON f."order" = o.id
              JOIN classes c ON o.class = c.id
              WHERE s.status = 'active'
              LIMIT 1
              ''',
            )).first['id']
            as String,
      );
      expect(species, isNotNull);

      final genusName = species!.classification.genusScientificName;
      final entityKey = 'genus:${genusName.toLowerCase()}';

      await userDb.insert('inat_taxonomy_common_names', {
        'entity_key': entityKey,
        'language_code': 'en',
        'names': 'iNat Genus Name',
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      });

      final enrichedSpecies = await repository.getSpeciesById(species.id);
      final genusCommonNames =
          enrichedSpecies!.classification.genusCommonNames[Language.en] ?? '';

      expect(genusCommonNames.split(';').first.trim(), 'iNat Genus Name');
    },
  );
}
