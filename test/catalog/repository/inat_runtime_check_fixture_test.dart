import 'dart:io';
import 'dart:math';

import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/repository/external_id_rejection_repository.dart';
import 'package:discere/catalog/repository/inat_allowed_ancestor_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The ETL's rejections and allowed ancestors as the curated fixture carries
/// them: the great white shark's class Elasmobranchii fits iNaturalist's
/// Chordata (2) and Chondrichthyes (196614), and the order Testudines was
/// rejected (iNaturalist's taxon of that name sits in another class).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database referenceDb;
  late String referenceDbPath;

  setUp(() async {
    final suffix =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
    referenceDbPath = join(
      Directory.systemTemp.path,
      'inat_runtime_check_$suffix.db',
    );
    await File(referenceDbPath).writeAsBytes(
      await File('test/fixtures/discere_reference_test.db').readAsBytes(),
      flush: true,
    );
    referenceDb = await openDatabase(referenceDbPath);
  });

  tearDown(() async {
    await referenceDb.close();
    await File(referenceDbPath).delete();
  });

  test('reads what fits a species and a higher taxon', () async {
    final repository = INatAllowedAncestorRepository(
      referenceDatabase: referenceDb,
    );

    expect(
      (await repository.requirementForSpecies('discere:class:3'))?.anyOf,
      [
        {2},
      ],
    );
    expect(
      (await repository.requirementForHigherTaxon(
        TaxonRank.genus,
        'Carcharodon',
      ))?.anyOf,
      [
        {2},
        {196614},
      ],
    );
  });

  test('reads a rejection', () async {
    final repository = ExternalIdRejectionRepository(
      referenceDatabase: referenceDb,
    );

    expect(
      await repository.isRejected(
        'order:testudines',
        ExternalIdProvider.inaturalist,
      ),
      isTrue,
    );
    expect(
      await repository.isRejected(
        'discere:species:694',
        ExternalIdProvider.inaturalist,
      ),
      isFalse,
    );
  });
}
