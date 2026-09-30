import 'dart:io';
import 'dart:math';

import 'package:discere/catalog/repository/inat_reference_resolver.dart';
import 'package:discere/external/inaturalist/inat_api_client.dart';
import 'package:discere/external/inaturalist/inat_search_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the online-search branch: what `INatReferenceResolver` does with
/// an iNaturalist hit that the bundled reference DB may or may not know.
///
/// The reference DB is built here rather than read from
/// `test/fixtures/discere_reference_test.db`, because these tests need both
/// halves of every case — a taxon that *is* in the reference DB and one
/// that deliberately is not — and the fixture's 27 curated species cannot
/// guarantee either side. The schema is the five name columns this resolver
/// actually queries (`genera`/`species` for the binomial join, plus the
/// three higher-rank tables), not a copy of the FTS-heavy schema in
/// `search_repository_test.dart`: the resolver runs no FTS at all, so
/// sharing that helper would mean seeding seven virtual tables to test
/// queries that never touch them.
class _FakeINatSearchApi extends INatSearchApi {
  final List<Map<String, dynamic>> _results;
  int callCount = 0;

  _FakeINatSearchApi(this._results)
    : super(api: INatApiClient(client: http.Client()));

  @override
  Future<List<Map<String, dynamic>>> searchTaxa(
    String query, {
    int perPage = 20,
  }) async {
    callCount++;
    return _results;
  }
}

/// One iNat search result in the shape `INatSearchApi.searchTaxa` returns.
Map<String, dynamic> _iNatResult({
  required String scientificName,
  required String rank,
  String? preferredCommonName,
}) => <String, dynamic>{
  'id': 42,
  'scientific_name': scientificName,
  'rank': rank,
  'preferred_common_name': preferredCommonName,
};

Future<Database> _openReferenceDatabase() async {
  final suffix =
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(10000)}';
  final path = join(
    Directory.systemTemp.path,
    'test_inat_reference_$suffix.db',
  );
  final db = await openDatabase(path);

  await db.execute('''
    CREATE TABLE genera (
      id   TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE species (
      id     TEXT NOT NULL PRIMARY KEY,
      genus  TEXT NOT NULL,
      name   TEXT NOT NULL,
      status TEXT NOT NULL
    )
  ''');
  for (final table in const ['families', 'orders', 'classes']) {
    await db.execute('''
      CREATE TABLE $table (
        id   TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL
      )
    ''');
  }

  await db.insert('genera', {'id': 'genus-1', 'name': 'Carcharodon'});
  await db.insert('species', {
    'id': 'species-1',
    'genus': 'genus-1',
    'name': 'carcharias',
    'status': 'active',
  });
  await db.insert('families', {'id': 'family-1', 'name': 'Lamnidae'});
  await db.insert('orders', {'id': 'order-1', 'name': 'Lamniformes'});
  await db.insert('classes', {'id': 'class-1', 'name': 'Chondrichthyes'});

  return db;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('INatReferenceResolver.searchAndResolveINat', () {
    late Database referenceDb;
    var referenceDatabaseCalls = 0;

    INatReferenceResolver resolverFor(INatSearchApi? iNatSearch) =>
        INatReferenceResolver(
          referenceDatabase: () async {
            referenceDatabaseCalls++;
            return referenceDb;
          },
          iNatSearch: iNatSearch,
        );

    setUp(() async {
      referenceDatabaseCalls = 0;
      referenceDb = await _openReferenceDatabase();
    });

    tearDown(() async {
      await referenceDb.close();
      final file = File(referenceDb.path);
      if (file.existsSync()) file.deleteSync();
    });

    test('a species known to the reference DB carries its reference id',
        () async {
      final resolver = resolverFor(
        _FakeINatSearchApi([
          _iNatResult(
            scientificName: 'Carcharodon carcharias',
            rank: 'species',
          ),
        ]),
      );

      final rows = await resolver.searchAndResolveINat('great white');

      expect(rows, hasLength(1));
      expect(rows.single['id'], 'species-1');
      expect(rows.single['entity_type'], 'species');
      expect(rows.single['scientific_name'], 'Carcharodon carcharias');
    });

    test('a subspecies resolves to its binomial species row', () async {
      // `searchTaxa` asks iNat for subspecies too, and the reference DB
      // only carries binomials — so the third name part is dropped.
      final resolver = resolverFor(
        _FakeINatSearchApi([
          _iNatResult(
            scientificName: 'Carcharodon carcharias albus',
            rank: 'subspecies',
          ),
        ]),
      );

      final rows = await resolver.searchAndResolveINat('great white');

      expect(rows, hasLength(1));
      expect(rows.single['id'], 'species-1');
    });

    test('a species the reference DB does not know yields no row', () async {
      // Deliberate, and the single least obvious thing in this class: the
      // synthetic `inat:` fallback exists for higher ranks only, because
      // `_entityTypeForINatRank` goes through `TaxonRank`, which has no
      // `species` value. A species-level iNat hit without a reference row
      // is therefore dropped rather than shown — showing it would offer a
      // card with no taxonomy, no pictures and no detail page behind it.
      final resolver = resolverFor(
        _FakeINatSearchApi([
          _iNatResult(
            scientificName: 'Amphiprion ocellaris',
            rank: 'species',
            preferredCommonName: 'Clown anemonefish',
          ),
        ]),
      );

      final rows = await resolver.searchAndResolveINat('clownfish');

      expect(rows, isEmpty);
    });

    test('a higher rank without a reference match becomes an inat: row',
        () async {
      final resolver = resolverFor(
        _FakeINatSearchApi([
          _iNatResult(
            scientificName: 'Pomacentridae',
            rank: 'family',
            preferredCommonName: 'Damselfishes',
          ),
        ]),
      );

      final rows = await resolver.searchAndResolveINat('damselfish');

      expect(rows, hasLength(1));
      expect(rows.single['id'], 'inat:families:pomacentridae');
      expect(rows.single['entity_type'], 'families');
      expect(rows.single['scientific_name'], 'Pomacentridae');
      expect(rows.single['common_name_en'], 'Damselfishes');
    });

    test('each higher rank gets its own inat: entity-type prefix', () async {
      final resolver = resolverFor(
        _FakeINatSearchApi([
          _iNatResult(scientificName: 'Amphiprion', rank: 'genus'),
          _iNatResult(scientificName: 'Pomacentridae', rank: 'family'),
          _iNatResult(scientificName: 'Perciformes', rank: 'order'),
          _iNatResult(scientificName: 'Actinopterygii', rank: 'class'),
        ]),
      );

      final rows = await resolver.searchAndResolveINat('fish');

      expect(rows.map((row) => row['id']), [
        'inat:genera:amphiprion',
        'inat:families:pomacentridae',
        'inat:orders:perciformes',
        'inat:classes:actinopterygii',
      ]);
    });

    test('a higher rank with a reference match gets no extra inat: row',
        () async {
      final resolver = resolverFor(
        _FakeINatSearchApi([
          _iNatResult(scientificName: 'Lamnidae', rank: 'family'),
        ]),
      );

      final rows = await resolver.searchAndResolveINat('mackerel shark');

      expect(rows, hasLength(1));
      expect(rows.single['id'], 'family-1');
      expect(
        rows.map((row) => row['id'] as String),
        isNot(contains(startsWith('inat:'))),
      );
    });

    test('a reference match is found regardless of case and padding', () async {
      final resolver = resolverFor(
        _FakeINatSearchApi([
          _iNatResult(scientificName: '  LAMNIDAE ', rank: 'family'),
        ]),
      );

      final rows = await resolver.searchAndResolveINat('lamnidae');

      expect(rows, hasLength(1));
      expect(rows.single['id'], 'family-1');
    });

    test('the iNat preferred English name rides along separately', () async {
      // The resolved rows carry no `common_name_*` columns of their own —
      // `SearchRepository` merges those itself. The live iNat name is the
      // one thing only this resolver sees, so it is attached under its own
      // key instead of being written into `common_name_en`.
      final resolver = resolverFor(
        _FakeINatSearchApi([
          _iNatResult(
            scientificName: 'Carcharodon carcharias',
            rank: 'species',
            preferredCommonName: 'Great white shark',
          ),
        ]),
      );

      final rows = await resolver.searchAndResolveINat('great white');

      expect(
        rows.single[INatReferenceResolver.inatPreferredCommonNameEnKey],
        'Great white shark',
      );
      expect(rows.single.containsKey('common_name_en'), isFalse);
    });

    test('a matched row without an iNat name gets no extra key', () async {
      final resolver = resolverFor(
        _FakeINatSearchApi([
          _iNatResult(
            scientificName: 'Carcharodon carcharias',
            rank: 'species',
          ),
        ]),
      );

      final rows = await resolver.searchAndResolveINat('great white');

      expect(
        rows.single.containsKey(
          INatReferenceResolver.inatPreferredCommonNameEnKey,
        ),
        isFalse,
      );
    });

    test('an unknown rank or an empty name is skipped', () async {
      final resolver = resolverFor(
        _FakeINatSearchApi([
          _iNatResult(scientificName: 'Animalia', rank: 'kingdom'),
          _iNatResult(scientificName: 'Chordata', rank: 'phylum'),
          _iNatResult(scientificName: '', rank: 'family'),
          _iNatResult(scientificName: '   ', rank: 'genus'),
        ]),
      );

      final rows = await resolver.searchAndResolveINat('animal');

      expect(rows, isEmpty);
    });

    test('an empty iNat response short-circuits before the DB', () async {
      final resolver = resolverFor(_FakeINatSearchApi(const []));

      expect(await resolver.searchAndResolveINat('nothing'), isEmpty);
      expect(referenceDatabaseCalls, 0);
    });

    test('without an iNat client nothing is searched at all', () async {
      final resolver = resolverFor(null);

      expect(await resolver.searchAndResolveINat('great white'), isEmpty);
      expect(referenceDatabaseCalls, 0);
    });

    test('the iNat API is asked exactly once per search', () async {
      final api = _FakeINatSearchApi([
        _iNatResult(scientificName: 'Lamnidae', rank: 'family'),
      ]);

      await resolverFor(api).searchAndResolveINat('mackerel shark');

      expect(api.callCount, 1);
    });
  });
}
