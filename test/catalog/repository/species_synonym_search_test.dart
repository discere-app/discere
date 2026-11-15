import 'package:discere/catalog/repository/species_synonym_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Against a hand-built database rather than the reference-DB fixture: the
/// fixture's FTS tables are FTS4, which the host's SQLite does not provide.
/// The names are the ones the reference DB carries.
void main() {
  late Database db;
  late SpeciesSynonymSearch synonyms;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('CREATE TABLE genera (id TEXT, name TEXT)');
    await db.execute(
      'CREATE TABLE species '
      '(id TEXT, external_source TEXT, genus TEXT, name TEXT, status TEXT)',
    );
    await db.execute(
      'CREATE TABLE species_scientific_names '
      '(species_id TEXT, name TEXT, source TEXT, is_preferred INTEGER)',
    );
    synonyms = SpeciesSynonymSearch(() async => db);
  });

  tearDown(() => db.close());

  Future<void> createSynonymTable() => db.execute(
    'CREATE VIRTUAL TABLE species_synonyms_fts '
    'USING fts5(species_id UNINDEXED, name)',
  );

  Future<void> addSpecies(
    String id,
    String genus,
    String epithet, {
    List<String> synonyms = const [],
    String status = 'active',
  }) async {
    await db.insert('genera', {'id': 'genus:$genus', 'name': genus});
    await db.insert('species', {
      'id': id,
      'genus': 'genus:$genus',
      'name': epithet,
      'status': status,
    });
    for (final synonym in synonyms) {
      await db.insert('species_synonyms_fts', {
        'species_id': id,
        'name': synonym,
      });
    }
  }

  Future<List<(String, String, String)>> search(
    String wildcardTerm,
    String normalizedSearchTerm,
  ) async => [
    for (final row in await synonyms.search(wildcardTerm, normalizedSearchTerm))
      (
        row['id'] as String,
        row['scientific_name'] as String,
        row['matched_synonym'] as String,
      ),
  ];

  group('with the synonym table', () {
    setUp(createSynonymTable);

    test('finds a species under a synonym, named as it is now', () async {
      await addSpecies(
        'discere:species:100205',
        'Pygmaeconus',
        'papalis',
        synonyms: ['Conus coronatus'],
      );

      expect(await search('Conus coronatus*', 'conus coronatus'), [
        ('discere:species:100205', 'Pygmaeconus papalis', 'Conus coronatus'),
      ]);
    });

    test('finds every species a synonym belongs to', () async {
      for (final (id, genus, epithet) in [
        ('discere:species:15300', 'Pterocryptis', 'wynaadensis'),
        ('discere:species:278', 'Ictalurus', 'punctatus'),
        ('discere:species:6051', 'Silurus', 'asotus'),
      ]) {
        await addSpecies(id, genus, epithet, synonyms: ['Silurus punctatus']);
      }

      expect(
        (await search(
          'Silurus punctatus*',
          'silurus punctatus',
        )).map((row) => row.$2),
        unorderedEquals([
          'Pterocryptis wynaadensis',
          'Ictalurus punctatus',
          'Silurus asotus',
        ]),
      );
    });

    test('finds a species once when several of its synonyms match', () async {
      await addSpecies(
        'discere:species:10',
        'Scyris',
        'indica',
        synonyms: ['Alectis indicus', 'Alectis indica'],
      );

      expect(await search('Alectis ind*', 'alectis ind'), [
        ('discere:species:10', 'Scyris indica', 'Alectis indica'),
      ]);
    });

    test('of several matching synonyms, the closest match is the one '
        'shown, before the alphabet', () async {
      await addSpecies(
        'species:a',
        'Apogon',
        'imberbis',
        synonyms: ['Amia imberbis', 'Imberbis apogon'],
      );

      expect(await search('imberbis*', 'imberbis'), [
        ('species:a', 'Apogon imberbis', 'Imberbis apogon'),
      ]);
    });

    test('when more species match than it returns, the closest matches '
        'are kept, before the alphabet', () async {
      for (var i = 0; i < 25; i++) {
        await addSpecies(
          'species:other$i',
          'Genus$i',
          'species$i',
          synonyms: ['Abramis amia$i'],
        );
      }
      await addSpecies(
        'species:exact',
        'Apogon',
        'imberbis',
        synonyms: ['Amia'],
      );

      final rows = await search('Amia*', 'amia');

      expect(rows, hasLength(20));
      expect(rows.map((row) => row.$1), contains('species:exact'));
    });

    test('leaves out a species that is no longer active', () async {
      await addSpecies(
        'species:deprecated',
        'Apogon',
        'imberbis',
        synonyms: ['Amia imberbis'],
        status: 'deprecated',
      );

      expect(await search('Amia imberbis*', 'amia imberbis'), isEmpty);
    });

    test('finds nothing when no synonym matches', () async {
      await addSpecies(
        'discere:species:10',
        'Scyris',
        'indica',
        synonyms: ['Alectis indica'],
      );

      expect(await search('Caranx*', 'caranx'), isEmpty);
    });
  });

  test('finds nothing in a reference database without the synonym '
      'table', () async {
    await addSpecies('discere:species:10', 'Scyris', 'indica');

    expect(await search('Alectis indica*', 'alectis indica'), isEmpty);
  });
}
