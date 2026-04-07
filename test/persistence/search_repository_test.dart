import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/model/language.dart';
import 'package:discere/model/search/search_result.dart';
import 'package:discere/persistence/downloaded_name_search_repository.dart';
import 'package:discere/persistence/search_repository.dart';
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
initializeSearchDatabases() async {
  final tempDir = Directory.systemTemp;
  final suffix =
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  final referenceDbPath = join(
    tempDir.path,
    'test_reference_search_$suffix.db',
  );
  final userDbPath = join(tempDir.path, 'test_user_search_$suffix.db');

  final referenceDb = await openDatabase(referenceDbPath);
  final userDb = await openDatabase(userDbPath);

  await _createReferenceSearchSchema(referenceDb);
  await _seedReferenceSearchData(referenceDb);

  await userDb.execute('''
    CREATE TABLE downloaded_name_search_documents (
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
  await _createDownloadedNameSearchFtsTable(userDb);

  return (referenceDb, userDb, referenceDbPath, userDbPath);
}

class _FakeINaturalistService extends INaturalistService {
  final List<Map<String, dynamic>> _results;
  int callCount = 0;

  _FakeINaturalistService(this._results);

  @override
  Future<List<Map<String, dynamic>>> searchTaxa(
    String query, {
    int perPage = 20,
  }) async {
    callCount++;
    return _results;
  }
}

class _ControlledReferenceDatabase implements Database {
  final Completer<List<Map<String, Object?>>> firstQueryCompleter =
      Completer<List<Map<String, Object?>>>();
  int rawQueryCallCount = 0;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    rawQueryCallCount++;
    if (rawQueryCallCount == 1) {
      return firstQueryCompleter.future;
    }
    return <Map<String, Object?>>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SerializedReferenceDatabase implements Database {
  final Completer<List<Map<String, Object?>>> firstQueryCompleter =
      Completer<List<Map<String, Object?>>>();
  int rawQueryCallCount = 0;
  int concurrentQueries = 0;
  int maxConcurrentQueries = 0;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    rawQueryCallCount++;
    concurrentQueries++;
    if (concurrentQueries > maxConcurrentQueries) {
      maxConcurrentQueries = concurrentQueries;
    }

    try {
      if (rawQueryCallCount == 1) {
        return await firstQueryCompleter.future;
      }
      return <Map<String, Object?>>[];
    } finally {
      concurrentQueries--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CapturingReferenceDatabase implements Database {
  String? lastWildcardTerm;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    if (arguments != null && arguments.isNotEmpty) {
      lastWildcardTerm = arguments.first as String?;
    }
    return <Map<String, Object?>>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _createReferenceSearchSchema(Database db) async {
  await db.execute('''
    CREATE TABLE genera (
      id   TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE species (
      id             TEXT NOT NULL PRIMARY KEY,
      genus          TEXT NOT NULL,
      name           TEXT NOT NULL,
      status         TEXT NOT NULL,
      common_name_en TEXT,
      common_name_de TEXT,
      common_name_fr TEXT,
      common_name_es TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE families (
      id             TEXT NOT NULL PRIMARY KEY,
      name           TEXT NOT NULL,
      common_name_en TEXT,
      common_name_de TEXT,
      common_name_fr TEXT,
      common_name_es TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE orders (
      id             TEXT NOT NULL PRIMARY KEY,
      name           TEXT NOT NULL,
      common_name_en TEXT,
      common_name_de TEXT,
      common_name_fr TEXT,
      common_name_es TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE classes (
      id   TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL
    )
  ''');

  await _createReferenceFtsTable(
    db,
    tableName: 'species_fts',
    columns:
        'id, name, common_name_en, common_name_de, common_name_fr, common_name_es',
  );
  await _createReferenceFtsTable(
    db,
    tableName: 'species_names_fts',
    columns: 'species_id, common_name',
  );
  await _createReferenceFtsTable(
    db,
    tableName: 'genera_fts',
    columns: 'id, name',
  );
  await _createReferenceFtsTable(
    db,
    tableName: 'families_fts',
    columns:
        'id, name, common_name_en, common_name_de, common_name_fr, common_name_es',
  );
  await _createReferenceFtsTable(
    db,
    tableName: 'orders_fts',
    columns:
        'id, name, common_name_en, common_name_de, common_name_fr, common_name_es',
  );
  await _createReferenceFtsTable(
    db,
    tableName: 'classes_fts',
    columns: 'id, name',
  );
}

Future<void> _seedReferenceSearchData(Database db) async {
  await db.insert('genera', {'id': 'genus-1', 'name': 'Carcharodon'});
  await db.insert('species', {
    'id': 'species-1',
    'genus': 'genus-1',
    'name': 'carcharias',
    'status': 'active',
    'common_name_en': 'Great white shark',
    'common_name_de': 'Weisser Hai',
    'common_name_fr': 'Grand requin blanc',
    'common_name_es': 'Tiburon blanco',
  });
  await db.insert('families', {
    'id': 'family-1',
    'name': 'Lamnidae',
    'common_name_en': 'Mackerel sharks',
    'common_name_de': 'Makrelenhaie',
    'common_name_fr': 'Requins maquereaux',
    'common_name_es': 'Tiburones caballa',
  });
  await db.insert('orders', {
    'id': 'order-1',
    'name': 'Lamniformes',
    'common_name_en': 'Mackerel shark allies',
    'common_name_de': 'Makrelenhaiartige',
    'common_name_fr': 'Lamniformes',
    'common_name_es': 'Lamniformes',
  });
  await db.insert('classes', {'id': 'class-1', 'name': 'Chondrichthyes'});

  await db.insert('species_fts', {
    'id': 'species-1',
    'name': 'carcharias',
    'common_name_en': 'Great white shark',
    'common_name_de': 'Weisser Hai',
    'common_name_fr': 'Grand requin blanc',
    'common_name_es': 'Tiburon blanco',
  });
  await db.insert('species_names_fts', {
    'species_id': 'species-1',
    'common_name': 'Great white shark',
  });
  await db.insert('genera_fts', {'id': 'genus-1', 'name': 'Carcharodon'});
  await db.insert('families_fts', {
    'id': 'family-1',
    'name': 'Lamnidae',
    'common_name_en': 'Mackerel sharks',
    'common_name_de': 'Makrelenhaie',
    'common_name_fr': 'Requins maquereaux',
    'common_name_es': 'Tiburones caballa',
  });
  await db.insert('orders_fts', {
    'id': 'order-1',
    'name': 'Lamniformes',
    'common_name_en': 'Mackerel shark allies',
    'common_name_de': 'Makrelenhaiartige',
    'common_name_fr': 'Lamniformes',
    'common_name_es': 'Lamniformes',
  });
  await db.insert('classes_fts', {'id': 'class-1', 'name': 'Chondrichthyes'});
}

Future<void> _createReferenceFtsTable(
  Database db, {
  required String tableName,
  required String columns,
}) async {
  try {
    await db.execute('''
      CREATE VIRTUAL TABLE $tableName USING fts5(
        $columns,
        tokenize = 'unicode61'
      )
    ''');
  } on DatabaseException {
    await db.execute('''
      CREATE VIRTUAL TABLE $tableName USING fts4(
        $columns,
        tokenize=unicode61
      )
    ''');
  }
}

Future<void> _createDownloadedNameSearchFtsTable(Database db) async {
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
      CREATE VIRTUAL TABLE downloaded_name_search_fts USING fts5(
        $ftsColumns,
        tokenize = 'unicode61'
      )
    ''');
  } on DatabaseException {
    await db.execute('''
      CREATE VIRTUAL TABLE downloaded_name_search_fts USING fts4(
        $ftsColumns,
        tokenize=unicode61
      )
    ''');
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database referenceDb;
  late Database userDb;
  late String referenceDbPath;
  late String userDbPath;
  late SearchRepository searchRepository;
  late DownloadedNameSearchRepository downloadedSearchRepository;

  setUp(() async {
    final dbs = await initializeSearchDatabases();
    referenceDb = dbs.$1;
    userDb = dbs.$2;
    referenceDbPath = dbs.$3;
    userDbPath = dbs.$4;
    searchRepository = SearchRepository(
      database: referenceDb,
      userDatabase: userDb,
    );
    downloadedSearchRepository = DownloadedNameSearchRepository(
      database: userDb,
    );
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

  test('downloaded species names create new search hits', () async {
    await downloadedSearchRepository.upsertDocument(
      const DownloadedNameSearchDocument(
        entityKey: 'species:species-1',
        entityId: 'species-1',
        entityType: 'species',
        scientificName: 'Carcharodon carcharias',
        commonNameEn: 'Lagoon clownfish',
      ),
    );

    final results = await searchRepository.searchAll('Lagoon');

    expect(
      results.where((result) => result.type == SearchEntityType.species),
      isNotEmpty,
    );
    expect(
      results.any(
        (result) => (result.commonNames[Language.en] ?? '').contains(
          'Lagoon clownfish',
        ),
      ),
      isTrue,
    );
  });

  test('downloaded taxonomy names create new search hits', () async {
    await downloadedSearchRepository.upsertDocument(
      const DownloadedNameSearchDocument(
        entityKey: 'genus:testgenus',
        entityId: 'genus:testgenus',
        entityType: 'genera',
        scientificName: 'Testgenus',
        commonNameEn: 'Harbor sprites',
      ),
    );

    final results = await searchRepository.searchAll('Harbor');

    expect(
      results.any((result) => result.type == SearchEntityType.genus),
      isTrue,
    );
    expect(results.first.name, 'Testgenus');
  });

  test(
    'batched search document upserts replace existing entries by entity key',
    () async {
      await downloadedSearchRepository.upsertDocuments([
        const DownloadedNameSearchDocument(
          entityKey: 'species:species-1',
          entityId: 'species-1',
          entityType: 'species',
          scientificName: 'Carcharodon carcharias',
          commonNameEn: 'Old river trout',
        ),
        const DownloadedNameSearchDocument(
          entityKey: 'species:species-1',
          entityId: 'species-1',
          entityType: 'species',
          scientificName: 'Carcharodon carcharias',
          commonNameEn: 'Fresh river trout',
        ),
      ]);

      final documents = await userDb.query(
        DownloadedNameSearchRepository.documentsTable,
        where: 'entity_key = ?',
        whereArgs: ['species:species-1'],
      );

      expect(documents.length, 1);
      expect(documents.first['common_name_en'], 'Fresh river trout');

      final results = await searchRepository.searchAll('Fresh');
      expect(results.where((result) => result.id == 'species-1').length, 1);
    },
  );

  test(
    'reference-only hits stay searchable through the reference index',
    () async {
      final results = await searchRepository.searchAll('Makrelen');

      expect(results, isNotEmpty);
      expect(
        results.any((result) => result.type == SearchEntityType.family),
        isTrue,
      );
    },
  );

  test('local hits skip the iNat fallback lookup', () async {
    final fakeINat = _FakeINaturalistService([
      {
        'id': 123,
        'scientific_name': 'Salmo trutta',
        'preferred_common_name': 'Brown Trout',
        'matched_term': 'Forelle',
      },
    ]);
    final repoWithINat = SearchRepository(
      database: referenceDb,
      userDatabase: userDb,
      iNatService: fakeINat,
    );

    final results = await repoWithINat.searchAll('Makrelen');

    expect(results, isNotEmpty);
    expect(fakeINat.callCount, 0);
  });

  test('quick search stays on the lightweight reference-only path', () async {
    await downloadedSearchRepository.upsertDocument(
      const DownloadedNameSearchDocument(
        entityKey: 'species:species-1',
        entityId: 'species-1',
        entityType: 'species',
        scientificName: 'Carcharodon carcharias',
        commonNameEn: 'Lagoon clownfish',
      ),
    );

    final fakeINat = _FakeINaturalistService([
      {
        'id': 123,
        'scientific_name': 'Salmo trutta',
        'rank': 'species',
        'preferred_common_name': 'Brown Trout',
        'matched_term': 'Forelle',
      },
    ]);
    final repoWithINat = SearchRepository(
      database: referenceDb,
      userDatabase: userDb,
      iNatService: fakeINat,
    );

    final results = await repoWithINat.searchQuick('Lagoon');

    expect(results, isEmpty);
    expect(fakeINat.callCount, 0);
  });

  test(
    'quick search skips the expensive reference fallback when FTS misses',
    () async {
      await referenceDb.insert('genera', {
        'id': 'genus-2',
        'name': 'Enteroctopus',
      });
      await referenceDb.insert('species', {
        'id': 'species-2',
        'genus': 'genus-2',
        'name': 'dofleini',
        'status': 'active',
        'common_name_en': 'Giant Pacific octopus',
        'common_name_de': 'Riesenpazifischer Oktopus',
        'common_name_fr': 'Poulpe geant du Pacifique',
        'common_name_es': 'Pulpo gigante del Pacifico',
      });

      final results = await searchRepository.searchQuick(
        'giant pacific octopus',
      );

      expect(results, isEmpty);
    },
  );

  test('quick search does not return taxonomy-only FTS matches', () async {
    final results = await searchRepository.searchQuick('Makrelen');

    expect(results, isEmpty);
  });

  test(
    'quick search limits multiword FTS queries to the last two tokens without a prefix wildcard',
    () async {
      final referenceDb = _CapturingReferenceDatabase();
      final repo = SearchRepository(database: referenceDb);

      await repo.searchQuick('giant pacific octopus');

      expect(referenceDb.lastWildcardTerm, 'pacific octopus');
    },
  );

  test('quick search keeps the prefix wildcard for single-token queries', () async {
    final referenceDb = _CapturingReferenceDatabase();
    final repo = SearchRepository(database: referenceDb);

    await repo.searchQuick('octopus');

    expect(referenceDb.lastWildcardTerm, 'octopus*');
    },
  );

  test(
    'quick search stops after cancellation instead of continuing queued queries',
    () async {
      final referenceDb = _ControlledReferenceDatabase();
      final repo = SearchRepository(database: referenceDb);
      final searchFuture = repo.searchQuick('giant');

      await Future<void>.delayed(Duration.zero);
      repo.cancelCurrentSearch();
      referenceDb.firstQueryCompleter.complete(<Map<String, Object?>>[]);

      final results = await searchFuture;

      expect(results, isEmpty);
      expect(referenceDb.rawQueryCallCount, 1);
    },
  );

  test('quick searches are serialized on the reference database', () async {
    final referenceDb = _SerializedReferenceDatabase();
    final repo = SearchRepository(database: referenceDb);

    final firstSearch = repo.searchQuick('gian');
    await Future<void>.delayed(Duration.zero);

    final secondSearch = repo.searchQuick('giant');
    await Future<void>.delayed(Duration.zero);

    expect(referenceDb.rawQueryCallCount, 1);
    expect(referenceDb.maxConcurrentQueries, 1);

    referenceDb.firstQueryCompleter.complete(<Map<String, Object?>>[]);

    final results = await Future.wait([firstSearch, secondSearch]);

    expect(results, hasLength(2));
    expect(referenceDb.maxConcurrentQueries, 1);
  });

  test('reference fallback finds local common names when FTS misses', () async {
    await referenceDb.insert('genera', {'id': 'genus-2', 'name': 'Salmo'});
    await referenceDb.insert('species', {
      'id': 'species-2',
      'genus': 'genus-2',
      'name': 'trutta',
      'status': 'active',
      'common_name_en': 'Brown trout',
      'common_name_de': 'Forelle',
      'common_name_fr': 'Truite',
      'common_name_es': 'Trucha',
    });

    final results = await searchRepository.searchAll('forelle');

    expect(results, isNotEmpty);
    expect(
      results.any(
        (result) =>
            result.type == SearchEntityType.species &&
            result.name == 'Salmo trutta',
      ),
      isTrue,
    );
  });

  test(
    'reference and downloaded hits for the same species are deduped and merged',
    () async {
      await downloadedSearchRepository.upsertDocument(
        const DownloadedNameSearchDocument(
          entityKey: 'species:species-1',
          entityId: 'species-1',
          entityType: 'species',
          scientificName: 'Carcharodon carcharias',
          commonNameEn: 'Lagoon hunter',
        ),
      );

      final results = await searchRepository.searchAll('carcharias');
      final speciesResults = results
          .where((result) => result.type == SearchEntityType.species)
          .toList();

      expect(speciesResults.length, 1);
      expect(speciesResults.first.id, 'species-1');
      expect(
        speciesResults.first.commonNames[Language.en],
        contains('Lagoon hunter'),
      );
      expect(
        speciesResults.first.commonNames[Language.en],
        contains('Great white shark'),
      );
    },
  );

  test(
    'iNat scientific-name lookup falls back from trinomial to local binomial species',
    () async {
      await referenceDb.insert('genera', {
        'id': 'genus-3',
        'name': 'Oncorhynchus',
      });
      await referenceDb.insert('species', {
        'id': 'species-3',
        'genus': 'genus-3',
        'name': 'mykiss',
        'status': 'active',
        'common_name_en': 'Rainbow trout',
        'common_name_de': 'Regenbogenforelle',
        'common_name_fr': 'Truite arc-en-ciel',
        'common_name_es': 'Trucha arcoiris',
      });

      final repoWithINat = SearchRepository(
        database: referenceDb,
        userDatabase: userDb,
        iNatService: _FakeINaturalistService([
          {
            'id': 123,
            'scientific_name': 'Oncorhynchus mykiss gairdneri',
            'rank': 'species',
            'preferred_common_name': 'Columbia River Redband Trout',
            'matched_term': 'Columbia-River-Redband-Forelle',
          },
        ]),
      );
      final matches = await repoWithINat.searchAll('forelle');

      expect(
        matches.any(
          (result) =>
              result.type == SearchEntityType.species &&
              result.name == 'Oncorhynchus mykiss',
        ),
        isTrue,
      );
    },
  );

  test(
    'iNat taxonomy lookup maps higher-rank matches into local search results',
    () async {
      await referenceDb.insert('orders', {
        'id': 'order-2',
        'name': 'Scleractinia',
        'common_name_en': 'Stony corals',
        'common_name_de': 'Steinkorallen',
        'common_name_fr': 'Coraux durs',
        'common_name_es': 'Corales pétreos',
      });

      final repoWithINat = SearchRepository(
        database: referenceDb,
        userDatabase: userDb,
        iNatService: _FakeINaturalistService([
          {
            'id': 999,
            'scientific_name': 'Scleractinia',
            'rank': 'order',
            'preferred_common_name': 'Stony corals',
            'matched_term': 'Steinkoralle',
          },
        ]),
      );

      final matches = await repoWithINat.searchAll('steinkoralle');

      expect(
        matches.any(
          (result) =>
              result.type == SearchEntityType.order &&
              result.name == 'Scleractinia',
        ),
        isTrue,
      );
    },
  );

  test(
    'unmatched iNat taxonomy still appears as fallback search result',
    () async {
      final repoWithINat = SearchRepository(
        database: referenceDb,
        userDatabase: userDb,
        iNatService: _FakeINaturalistService([
          {
            'id': 1000,
            'scientific_name': 'Hexacorallia',
            'rank': 'class',
            'preferred_common_name': 'Hexacorals',
            'matched_term': 'Steinkoralle',
          },
        ]),
      );

      final matches = await repoWithINat.searchAll('steinkoralle');

      expect(
        matches.any(
          (result) =>
              result.type == SearchEntityType.classType &&
              result.name == 'Hexacorallia',
        ),
        isTrue,
      );
    },
  );

  test(
    'exact matches rank above prefix matches across merged sources',
    () async {
      await downloadedSearchRepository.upsertDocument(
        const DownloadedNameSearchDocument(
          entityKey: 'genus:lagoonia',
          entityId: 'genus:lagoonia',
          entityType: 'genera',
          scientificName: 'Lagoonia',
          commonNameEn: 'Lagoon fish',
        ),
      );

      await downloadedSearchRepository.upsertDocument(
        const DownloadedNameSearchDocument(
          entityKey: 'family:lagoonidae',
          entityId: 'family:lagoonidae',
          entityType: 'families',
          scientificName: 'Lagoonidae',
          commonNameEn: 'Lagoon',
        ),
      );

      final results = await searchRepository.searchAll('Lagoon');

      expect(results, isNotEmpty);
      expect(results.first.name, 'Lagoonidae');
    },
  );

  test(
    'fallback contains search finds downloaded names when prefix FTS misses',
    () async {
      await downloadedSearchRepository.upsertDocument(
        const DownloadedNameSearchDocument(
          entityKey: 'genus:lagoonia',
          entityId: 'genus:lagoonia',
          entityType: 'genera',
          scientificName: 'Lagoonia',
          commonNameEn: 'Lagoon clownfish allies',
        ),
      );

      final results = await searchRepository.searchAll('goon');

      expect(results, isNotEmpty);
      expect(results.first.name, 'Lagoonia');
    },
  );
}
