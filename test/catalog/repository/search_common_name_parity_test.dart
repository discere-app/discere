import 'dart:io';
import 'dart:math';

import 'package:discere/catalog/model/locale_place_mapping.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/repository/runtime_common_name_search_repository.dart';
import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/search/search_worker.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'runtime_common_names_test_schema.dart';

/// Regression coverage for GitHub issue #111: search results and the
/// species detail page must resolve the same primary common name for the
/// same species/locale, no matter which of `SearchRepository`'s two FTS
/// branches (reference vs. runtime-cached) found the hit. Both repositories
/// are wired against the *same* reference + user DB here so their outputs
/// can be compared directly, which neither `search_repository_test.dart`
/// nor `species_repository_common_names_test.dart` does on its own.
Future<void> _createRuntimeCommonNameSearchFtsTable(Database db) async {
  const ftsColumns = '''
    entity_key,
    scientific_name,
    common_name_en,
    common_name_de,
    common_name_fr,
    common_name_es
  ''';

  try {
    await db.execute('''
      CREATE VIRTUAL TABLE runtime_common_name_search_fts USING fts5(
        $ftsColumns,
        tokenize = 'unicode61'
      )
    ''');
  } on DatabaseException {
    await db.execute('''
      CREATE VIRTUAL TABLE runtime_common_name_search_fts USING fts4(
        $ftsColumns,
        tokenize=unicode61
      )
    ''');
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database referenceDb;
  late Database userDb;
  late String referenceDbPath;
  late String userDbPath;
  late SpeciesRepository speciesRepository;
  late SearchRepository searchRepository;
  late RuntimeCommonNameSearchRepository runtimeCommonNameSearchRepository;

  setUp(() async {
    final tempDir = Directory.systemTemp;
    final suffix =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
    referenceDbPath = join(tempDir.path, 'test_reference_parity_$suffix.db');
    userDbPath = join(tempDir.path, 'test_user_parity_$suffix.db');

    // Kuratierte Test-Fixture (kleine Untermenge der echten Referenz-DB,
    // siehe etl/scripts/build_test_fixture.sh) — needed (rather than a
    // synthetic schema) because it already has all the FTS tables
    // `SearchRepository` queries.
    final bytes = await File(
      'test/fixtures/discere_reference_test.db',
    ).readAsBytes();
    await File(referenceDbPath).writeAsBytes(bytes, flush: true);

    referenceDb = await openDatabase(referenceDbPath, readOnly: false);
    userDb = await openDatabase(userDbPath);
    await createRuntimeCommonNamesTable(userDb);
    await userDb.execute('''
      CREATE TABLE runtime_common_name_search_documents (
        entity_key             TEXT NOT NULL PRIMARY KEY,
        entity_id              TEXT NOT NULL,
        entity_type            TEXT NOT NULL,
        scientific_name        TEXT NOT NULL,
        common_name_en         TEXT,
        common_name_de         TEXT,
        common_name_fr         TEXT,
        common_name_es         TEXT,
        normalized_search_text TEXT NOT NULL
      )
    ''');
    await _createRuntimeCommonNameSearchFtsTable(userDb);

    speciesRepository = SpeciesRepository(
      database: referenceDb,
      userDatabase: userDb,
    );
    searchRepository = SearchRepository(
      database: referenceDb,
      userDatabase: userDb,
      searchWorker: SearchWorker(),
    );
    runtimeCommonNameSearchRepository = RuntimeCommonNameSearchRepository(
      database: userDb,
    );
  });

  tearDown(() async {
    await referenceDb.close();
    await userDb.close();
    await File(referenceDbPath).delete();
    await File(userDbPath).delete();
  });

  Future<({String id, String epithet, String genus})> rainbowTrout() async {
    final row = (await referenceDb.rawQuery('''
      SELECT s.id, s.name AS epithet, g.name AS genus
      FROM species s
      JOIN genera g ON g.id = s.genus
      WHERE s.name = 'mykiss'
    ''')).first;
    return (
      id: row['id'] as String,
      epithet: row['epithet'] as String,
      genus: row['genus'] as String,
    );
  }

  test(
    'search hit via the reference-FTS branch shows the same primary name as the detail page',
    () async {
      final species = await rainbowTrout();
      await userDb.insert('runtime_common_names', {
        'entity_key': 'species:${species.id}',
        'entity_type': 'species',
        'language_code': 'en',
        'name': 'Runtime Rainbow',
        'position': 1,
        'place_id': null,
        'place_position': null,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      });

      // The species epithet alone matches `species_fts` directly, so this
      // hit comes through `_searchReferenceFts`, never `runtime_common_name`
      // FTS.
      final searchResults = await searchRepository.searchAll(species.epithet);
      final searchHit = searchResults.singleWhere(
        (result) =>
            result.type == SearchEntityType.species && result.id == species.id,
      );

      final detailSpecies = await speciesRepository.getSpeciesById(
        species.id,
      );

      expect(detailSpecies, isNotNull);
      expect(
        detailSpecies!.commonNames[Language.en]!.first,
        'Runtime Rainbow',
      );
      expect(
        searchHit.commonNames[Language.en]!.first,
        detailSpecies.commonNames[Language.en]!.first,
      );
    },
  );

  test(
    'search hit via the runtime-FTS branch shows the same primary name as the detail page',
    () async {
      final species = await rainbowTrout();
      await userDb.insert('runtime_common_names', {
        'entity_key': 'species:${species.id}',
        'entity_type': 'species',
        'language_code': 'en',
        'name': 'Runtime Rainbow',
        'position': 1,
        'place_id': null,
        'place_position': null,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      });

      // A distinctive nickname that exists only in the runtime search-
      // document cache, absent from every reference FTS index, so this hit
      // can only come through `_searchRuntimeCommonNameFtsSafely`.
      await runtimeCommonNameSearchRepository.upsertDocument(
        RuntimeCommonNameSearchDocument(
          entityKey: 'species:${species.id}',
          entityId: species.id,
          entityType: 'species',
          scientificName: '${species.genus} ${species.epithet}',
          commonNameEn: 'Zzzsteelheadnickname',
        ),
      );

      final searchResults = await searchRepository.searchAll(
        'Zzzsteelheadnickname',
      );
      final searchHit = searchResults.singleWhere(
        (result) =>
            result.type == SearchEntityType.species && result.id == species.id,
      );

      final detailSpecies = await speciesRepository.getSpeciesById(
        species.id,
      );

      expect(detailSpecies, isNotNull);
      expect(
        detailSpecies!.commonNames[Language.en]!.first,
        'Runtime Rainbow',
      );
      expect(
        searchHit.commonNames[Language.en]!.first,
        detailSpecies.commonNames[Language.en]!.first,
      );
    },
  );

  test(
    'locale/place-aware ordering agrees between search and detail page',
    () async {
      final species = await rainbowTrout();
      const userPlaceId = 8057;
      const otherPlaceId = 7207;

      await userDb.insert('runtime_common_names', {
        'entity_key': 'species:${species.id}',
        'entity_type': 'species',
        'language_code': 'en',
        'name': 'Other-Region Nickname',
        'position': 1,
        'place_id': otherPlaceId,
        'place_position': 1,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      });
      await userDb.insert('runtime_common_names', {
        'entity_key': 'species:${species.id}',
        'entity_type': 'species',
        'language_code': 'en',
        'name': 'Home-Region Nickname',
        'position': 2,
        'place_id': userPlaceId,
        'place_position': 1,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      });

      const localeMapping = LocalePlaceMapping(
        locale: 'de_CH',
        languageCode: 'de',
        countryCodeAlpha2: 'CH',
        countryCodeNumeric: '756',
        inatPlaceId: userPlaceId,
      );
      final localeAwareSpeciesRepository = SpeciesRepository(
        database: referenceDb,
        userDatabase: userDb,
        localeMapping: localeMapping,
      );
      final localeAwareSearchRepository = SearchRepository(
        database: referenceDb,
        userDatabase: userDb,
        localeMapping: localeMapping,
        searchWorker: SearchWorker(),
      );

      final searchResults = await localeAwareSearchRepository.searchAll(
        species.epithet,
      );
      final searchHit = searchResults.singleWhere(
        (result) =>
            result.type == SearchEntityType.species && result.id == species.id,
      );
      final detailSpecies = await localeAwareSpeciesRepository.getSpeciesById(
        species.id,
      );

      expect(detailSpecies, isNotNull);
      expect(
        detailSpecies!.commonNames[Language.en]!.first,
        'Home-Region Nickname',
      );
      expect(
        searchHit.commonNames[Language.en]!.first,
        detailSpecies.commonNames[Language.en]!.first,
      );
    },
  );
}
