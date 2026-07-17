import 'dart:io';
import 'dart:math';

import 'package:discere/catalog/repository/species_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers [SpeciesRepository.getScientificNameCandidates], which was
/// previously untested despite the rest of species_repository.dart being
/// covered elsewhere (species_repository_common_names_test.dart,
/// species_repository_byscientificname_name_test.dart,
/// species_repository_batch_test.dart).
Future<(Database referenceDb, String referenceDbPath)> initializeReferenceDb() async {
  final tempDir = Directory.systemTemp;
  final suffix =
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  final referenceDbPath = join(tempDir.path, 'test_reference_$suffix.db');

  final data = await rootBundle.load('assets/database/discere_reference.db');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  await File(referenceDbPath).writeAsBytes(bytes, flush: true);

  final referenceDb = await openDatabase(referenceDbPath, readOnly: false);
  return (referenceDb, referenceDbPath);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database referenceDb;
  late String referenceDbPath;
  late SpeciesRepository repository;

  setUp(() async {
    final dbs = await initializeReferenceDb();
    referenceDb = dbs.$1;
    referenceDbPath = dbs.$2;
    repository = SpeciesRepository(database: referenceDb);
  });

  tearDown(() async {
    await referenceDb.close();
    final referenceFile = File(referenceDbPath);
    if (await referenceFile.exists()) {
      await referenceFile.delete();
    }
  });

  test(
    'returns the canonical scientific name as a deduplicated candidate',
    () async {
      final row = (await referenceDb.rawQuery('''
        SELECT species_id FROM species_scientific_names
        WHERE normalized_name = 'carcharodon carcharias'
        LIMIT 1
      ''')).first;
      final speciesId = row['species_id'] as String;

      final candidates = await repository.getScientificNameCandidates(
        speciesId,
      );

      expect(candidates, contains('Carcharodon carcharias'));
      expect(candidates.toSet().length, candidates.length);
    },
  );

  test(
    'puts the preferred scientific name first, ahead of database candidates',
    () async {
      final row = (await referenceDb.rawQuery('''
        SELECT species_id FROM species_scientific_names
        WHERE normalized_name = 'carcharodon carcharias'
        LIMIT 1
      ''')).first;
      final speciesId = row['species_id'] as String;

      final candidates = await repository.getScientificNameCandidates(
        speciesId,
        preferredScientificName: 'Zzztestus preferredus',
      );

      expect(candidates.first, 'Zzztestus preferredus');
      expect(candidates, contains('Carcharodon carcharias'));
    },
  );

  test(
    'does not duplicate the preferred name when it already matches a '
    'database candidate',
    () async {
      final row = (await referenceDb.rawQuery('''
        SELECT species_id FROM species_scientific_names
        WHERE normalized_name = 'carcharodon carcharias'
        LIMIT 1
      ''')).first;
      final speciesId = row['species_id'] as String;

      final candidates = await repository.getScientificNameCandidates(
        speciesId,
        // Different casing/whitespace than the canonical form, but the same
        // normalized binomial.
        preferredScientificName: '  CARCHARODON   CARCHARIAS  ',
      );

      expect(
        candidates.where((name) => name == 'Carcharodon carcharias').length,
        1,
      );
      expect(candidates.first, 'Carcharodon carcharias');
    },
  );

  test(
    'returns an empty list for an unknown species id with no preferred name',
    () async {
      final candidates = await repository.getScientificNameCandidates(
        'does-not-exist',
      );

      expect(candidates, isEmpty);
    },
  );

  test(
    'falls back to just the preferred name for an unknown species id',
    () async {
      final candidates = await repository.getScientificNameCandidates(
        'does-not-exist',
        preferredScientificName: 'Solus nominatus',
      );

      expect(candidates, ['Solus nominatus']);
    },
  );
}
