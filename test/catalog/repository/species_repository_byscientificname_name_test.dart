import 'dart:io';
import 'dart:math';

import 'package:discere/catalog/repository/species_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Map<String, dynamic>> initializeTestDatabase() async {
  // Build a unique file name for the test database in the system temp directory
  final tempDir = Directory.systemTemp;
  final uniqueSuffix =
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  final dbPath = join(tempDir.path, 'test_aquaflash_$uniqueSuffix.db');

  // Load the curated test fixture (a small subset of the real reference DB,
  // see etl/scripts/build_test_fixture.sh).
  final bytes = await File(
    'test/fixtures/discere_reference_test.db',
  ).readAsBytes();

  // Write the data to the temporary file
  await File(dbPath).writeAsBytes(bytes, flush: true);

  // Open the test database
  final database = await openDatabase(dbPath, readOnly: false);

  return {'database': database, 'dbPath': dbPath};
}

void main() {
  // Important: initialize the FFI backend so openDatabase works in the test environment.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Make sure the Flutter bindings are initialized.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late String dbPath;
  late SpeciesRepository repository;

  setUp(() async {
    // Initialize the temporary test database
    final dbData = await initializeTestDatabase();
    database = dbData['database'] as Database;
    dbPath = dbData['dbPath'] as String;

    // Initialize the repository with the test database
    repository = SpeciesRepository(database: database);

    // Insert further test data here if needed.
  });

  tearDown(() async {
    // Close the database
    await database.close();
    // Delete the temporary database file if it exists
    final file = File(dbPath);
    if (await file.exists()) {
      await file.delete();
    }
  });

  test('getSpeciesIdsByScientificNames returns the correct IDs', () async {
    // Arrange: build a list of (genus, species) tuples
    final scientificNames = [
      ('Carcharodon', 'carcharias'),
      ('Galeocerdo', 'cuvier'),
      ('Prionace', 'glauca'),
      ('Rhincodon', 'typus'),
      ('Sphyrna', 'mokarran'),
      ('Alopias', 'vulpinus'),
    ];

    final result = await repository.getSpeciesIdsByScientificNames(
      scientificNames,
    );

    // We test that it returns exactly 6 IDs. We don't check exact UUIDs
    // since the database uses UUIDs generated during ETL.
    expect(result.length, 6);
  });

  test('should return empty list for non-existing scientific name', () async {
    // Arrange
    final invalidScientificName = [('Invalidus', 'ficticius')];

    // Act
    final result = await repository.getSpeciesIdsByScientificNames(
      invalidScientificName,
    );

    // Assert
    expect(result, isEmpty);
  });

  test('should return empty list for empty scientific name', () async {
    // Act
    final result = await repository.getSpeciesIdsByScientificNames(
      <(String, String)>[],
    );

    // Assert
    expect(result, isEmpty);
  });

  group('resolveFullNames', () {
    test('resolves known full names to a name→id map', () async {
      final result = await repository.resolveFullNames([
        'Carcharodon carcharias',
        'Rhincodon typus',
      ]);

      expect(result.length, 2);
      expect(
        result.keys,
        containsAll(['Carcharodon carcharias', 'Rhincodon typus']),
      );
      // IDs are UUIDs — just verify they are non-empty strings
      for (final id in result.values) {
        expect(id, isNotEmpty);
      }
    });

    test('returns only resolved entries, omitting unknown names', () async {
      final result = await repository.resolveFullNames([
        'Carcharodon carcharias',
        'Invalidus ficticius',
      ]);

      expect(result.length, 1);
      expect(result.containsKey('Carcharodon carcharias'), isTrue);
      expect(result.containsKey('Invalidus ficticius'), isFalse);
    });

    test('returns empty map for empty input', () async {
      final result = await repository.resolveFullNames([]);
      expect(result, isEmpty);
    });

    test('returns empty map when no names match', () async {
      final result = await repository.resolveFullNames([
        'Invalidus ficticius',
        'Nemo existus',
      ]);
      expect(result, isEmpty);
    });

    test(
      'normalizes case, repeated whitespace, and extra scientific suffixes',
      () async {
        final result = await repository.resolveFullNames([
          '  carcharodon   carcharias  ',
          'Oncorhynchus mykiss gairdneri',
        ]);

        expect(result.containsKey('  carcharodon   carcharias  '), isTrue);
        expect(result.containsKey('Oncorhynchus mykiss gairdneri'), isTrue);
      },
    );

    test(
      'resolves FishBase synonyms to the same canonical species id',
      () async {
        final result = await repository.resolveFullNames([
          'Phoxinus phoxinus',
          'Phoxinus lumaireul',
          'Thymallus thymallus',
          'Thymallus aeliani',
        ]);

        expect(result['Phoxinus phoxinus'], isNotNull);
        expect(result['Phoxinus lumaireul'], result['Phoxinus phoxinus']);
        expect(result['Thymallus thymallus'], isNotNull);
        expect(result['Thymallus aeliani'], result['Thymallus thymallus']);
      },
    );

    test(
      'uses species_name_lookup when the materialized table exists',
      () async {
        final canonical = await database.rawQuery(
          '''
        SELECT species_id
        FROM species_scientific_names
        WHERE normalized_name = ?
        LIMIT 1
      ''',
          ['carcharodon carcharias'],
        );
        final speciesId = canonical.isEmpty
            ? null
            : canonical.first['species_id'] as String?;
        expect(speciesId, isNotNull);

        await database.insert('species_name_lookup', {
          'normalized_name': 'testus fishus',
          'species_id': speciesId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        final result = await repository.resolveFullNames(['Testus fishus']);
        expect(result['Testus fishus'], speciesId);
      },
    );

    test('is consistent with getSpeciesIdsByFullNames', () async {
      final names = ['Carcharodon carcharias', 'Galeocerdo cuvier'];
      final mapResult = await repository.resolveFullNames(names);
      final setResult = await repository.getSpeciesIdsByFullNames(names);

      expect(mapResult.values.toSet(), setResult);
    });
  });
}
