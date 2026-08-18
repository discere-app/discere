import 'dart:io';
import 'dart:math';

import 'package:discere/catalog/model/body_form.dart';
import 'package:discere/catalog/model/fishing_importance.dart';
import 'package:discere/catalog/model/habitat_tag.dart';
import 'package:discere/catalog/model/locale_place_mapping.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'runtime_common_names_test_schema.dart';

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
  await createRuntimeCommonNamesTable(userDb);

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
      SELECT s.id
      FROM species s
      JOIN common_names cn ON cn.entity_id = s.id
      WHERE cn.language IN ('fr', 'es')
      LIMIT 1
    ''')).first;

      final species = await repository.getSpeciesById(row['id'] as String);

      expect(species, isNotNull);
      expect(
        (species!.commonNames[Language.fr] ?? const []).isNotEmpty ||
            (species.commonNames[Language.es] ?? const []).isNotEmpty,
        isTrue,
      );
    },
  );

  test(
    'merges persisted iNat common names without duplicating normalized matches and keeps iNat first',
    () async {
      final row = (await referenceDb.rawQuery('''
      SELECT s.id, cn.name AS common_name_en
      FROM species s
      JOIN common_names cn ON cn.entity_id = s.id
      WHERE cn.language = 'en'
      LIMIT 1
    ''')).first;
      final speciesId = row['id'] as String;
      final existingEnglish = row['common_name_en'] as String;
      final firstExistingName = existingEnglish.trim();

      await userDb.insert('runtime_common_names', {
        'entity_key': 'species:$speciesId',
        'entity_type': 'species',
        'language_code': 'en',
        'name': 'Lagoon clownfish',
        'position': 1,
        'place_id': null,
        'place_position': null,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      });
      await userDb.insert('runtime_common_names', {
        'entity_key': 'species:$speciesId',
        'entity_type': 'species',
        'language_code': 'en',
        'name': '  ${firstExistingName.toUpperCase()}  ',
        'position': 2,
        'place_id': null,
        'place_position': null,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      });

      final species = await repository.getSpeciesById(speciesId);

      expect(species, isNotNull);
      final englishNames = species!.commonNames[Language.en] ?? const [];
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
        'name': 'iNat Genus Name',
        'position': 1,
        'place_id': null,
        'place_position': null,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      });

      final enrichedSpecies = await repository.getSpeciesById(species.id);
      final genusCommonNames =
          enrichedSpecies!.classification.genusCommonNames[Language.en] ??
          const [];

      expect(genusCommonNames.first.trim(), 'iNat Genus Name');
    },
  );

  test('prefers the user\'s regional common name for family/genus/order/class, '
      'just like it already does for species', () async {
    const userPlaceId = 8057;
    const otherPlaceId = 7207;
    final localeAwareRepository = SpeciesRepository(
      database: referenceDb,
      userDatabase: userDb,
      localeMapping: const LocalePlaceMapping(
        locale: 'de_CH',
        languageCode: 'de',
        countryCodeAlpha2: 'CH',
        countryCodeNumeric: '756',
        inatPlaceId: userPlaceId,
      ),
    );

    final species = await localeAwareRepository.getSpeciesById(
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

    final familyName = species!.classification.familyScientificName;
    final entityKey = 'family:${familyName.toLowerCase()}';

    // Global name is ranked best by iNat's own position, but the
    // user's own region should still win.
    await userDb.insert('runtime_common_names', {
      'entity_key': entityKey,
      'entity_type': 'family',
      'language_code': 'de',
      'name': 'Globaler Name',
      'position': 1,
      'place_id': null,
      'place_position': null,
      'fetched_at': DateTime.now().millisecondsSinceEpoch,
    });
    await userDb.insert('runtime_common_names', {
      'entity_key': entityKey,
      'entity_type': 'family',
      'language_code': 'de',
      'name': 'Anderer Regionsname',
      'position': 2,
      'place_id': otherPlaceId,
      'place_position': 0,
      'fetched_at': DateTime.now().millisecondsSinceEpoch,
    });
    await userDb.insert('runtime_common_names', {
      'entity_key': entityKey,
      'entity_type': 'family',
      'language_code': 'de',
      'name': 'Schweizer Name',
      'position': 3,
      'place_id': userPlaceId,
      'place_position': 0,
      'fetched_at': DateTime.now().millisecondsSinceEpoch,
    });

    final enrichedSpecies = await localeAwareRepository.getSpeciesById(
      species.id,
    );
    final familyCommonNames =
        enrichedSpecies!.classification.familyCommonNames[Language.de] ??
        const [];

    expect(familyCommonNames.first.trim(), 'Schweizer Name');
  });

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

    // The picked species may already carry real distribution data (e.g. a
    // widely-studied species with dozens of native-range rows) — clear it so
    // this test only ever sees the three rows it inserts below, regardless
    // of which species `LIMIT 1` happens to pick.
    await referenceDb.delete(
      'taxonomy_distribution_regions',
      where: 'entity_id = ?',
      whereArgs: [speciesId],
    );

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
    await referenceDb.insert(
      'taxonomy_distribution_regions',
      {
        'entity_id': speciesId,
        'entity_type': 'species',
        'source': 'fishbase',
        'region_scope': 'country',
        'region_key': 'JP',
        'region_label': 'JP',
        'presence_status': 'present',
        'establishment_status': 'endemic',
        'threatened_flag': 0,
        'abundance': null,
        'importance': null,
        'comment': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final species = await repository.getSpeciesById(speciesId);

    expect(species, isNotNull);
    expect(species!.dangerousToHumansRaw, 'venomous spines');
    expect(species.dangerousToHumans, isNull);
    expect(species.maxLengthCm, isNotNull);
    expect(species.fisheriesImportance, FishingImportance.commercial);
    expect(species.longevityYears, 12.5);
    expect(species.bodyShape, BodyForm.elongated);
    expect(species.trophicLevelFood, 3.8);
    expect(species.traits, containsAll([HabitatTag.stream, HabitatTag.reef]));
    expect(
      species.nativeRegions,
      contains(
        isA<dynamic>()
            .having((region) => region.label, 'label', 'CH')
            .having((region) => region.isThreatened, 'isThreatened', isTrue)
            .having(
              (region) => region.establishmentStatus,
              'establishmentStatus',
              'native',
            ),
      ),
    );
    expect(
      species.nativeRegions.where((region) => region.label == 'United States'),
      isEmpty,
    );
    expect(
      species.nativeRegions,
      contains(
        isA<dynamic>()
            .having((region) => region.label, 'label', 'JP')
            .having(
              (region) => region.establishmentStatus,
              'establishmentStatus',
              'endemic',
            ),
      ),
    );
  });
}
