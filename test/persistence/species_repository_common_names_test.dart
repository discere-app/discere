import 'dart:io';
import 'dart:math';

import 'package:discere/shared/model/language.dart';
import 'package:discere/catalog/repository/species_repository.dart';
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
    CREATE TABLE runtime_common_names (
      entity_key     TEXT NOT NULL,
      entity_type    TEXT NOT NULL,
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

      await userDb.insert('runtime_common_names', {
        'entity_key': 'species:$speciesId',
        'entity_type': 'species',
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
        (await referenceDb.rawQuery('''
              SELECT s.id
              FROM species s
              JOIN genera g ON s.genus = g.id
              JOIN families f ON g.family = f.id
              JOIN orders o ON f."order" = o.id
              JOIN classes c ON o.class = c.id
              WHERE s.status = 'active'
              LIMIT 1
              ''')).first['id']
            as String,
      );
      expect(species, isNotNull);

      final genusName = species!.classification.genusScientificName;
      final entityKey = 'genus:${genusName.toLowerCase()}';

      await userDb.insert('runtime_common_names', {
        'entity_key': entityKey,
        'entity_type': 'genus',
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

  test('maps extended facts, habitat traits and native regions', () async {
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
    final speciesId = row['id'] as String;

    await referenceDb.update(
      'species',
      {
        'dangerous_to_humans': 'venomous spines',
        'fisheries_importance': 'commercial',
        'longevity_years': 12.5,
        'body_shape': 'elongated',
        'trophic_level_food': 3.8,
      },
      where: 'id = ?',
      whereArgs: [speciesId],
    );

    await referenceDb.insert('taxonomy_traits', {
      'entity_id': speciesId,
      'entity_type': 'species',
      'trait_key': 'freshwater_stream_association',
      'trait_value_text': null,
      'trait_value_num': null,
      'trait_value_bool': 1,
      'source': 'fishbase',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await referenceDb.insert('taxonomy_traits', {
      'entity_id': speciesId,
      'entity_type': 'species',
      'trait_key': 'reef_association',
      'trait_value_text': null,
      'trait_value_num': null,
      'trait_value_bool': 1,
      'source': 'sealifebase',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await referenceDb.insert(
      'taxonomy_distribution_regions',
      {
        'entity_id': speciesId,
        'entity_type': 'species',
        'source': 'fishbase',
        'region_scope': 'country',
        'region_key': 'CH',
        'region_label': 'CH',
        'presence_status': 'present',
        'establishment_status': 'native',
        'threatened_flag': 1,
        'abundance': 'common',
        'importance': 'minor',
        'comment': 'test comment',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await referenceDb.insert(
      'taxonomy_distribution_regions',
      {
        'entity_id': speciesId,
        'entity_type': 'species',
        'source': 'fishbase',
        'region_scope': 'country',
        'region_key': 'US',
        'region_label': 'US',
        'presence_status': 'present',
        'establishment_status': 'introduced',
        'threatened_flag': 0,
        'abundance': 'rare',
        'importance': 'minor',
        'comment': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final species = await repository.getSpeciesById(speciesId);

    expect(species, isNotNull);
    expect(species!.dangerousToHumans, 'venomous spines');
    expect(species.fisheriesImportance, 'commercial');
    expect(species.longevityYears, '12.5 years');
    expect(species.bodyShape, 'elongated');
    expect(species.trophicLevelFood, '3.8');
    expect(
      species.traits,
      containsAll(['freshwater_stream_association', 'reef_association']),
    );
    expect(species.nativeRegions, hasLength(1));
    expect(species.nativeRegions.first.label, 'CH');
    expect(species.nativeRegions.first.isThreatened, isTrue);
  });
}
