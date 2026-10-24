import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/runtime_common_name_search_repository.dart';
import 'package:discere/enrichment/pipeline/repository/runtime_common_name_repository.dart';
import 'package:discere/external/inaturalist/models/inat_common_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

/// Covers the provenance stamp every stored name carries: the iNat taxon the
/// names came from, which the reconciliation after a reference-database
/// update holds against the taxon the entity maps to.

final _species = Species(
  'sp1',
  'sp1',
  'sealifebase',
  'pusilla',
  const {},
  Classification(
    'Triphora',
    const {},
    null,
    null,
    const {},
    null,
    const {},
    null,
    const {},
    null,
  ),
  const [],
);

const _names = {
  'en': [INatCommonName(languageCode: 'en', name: 'Little snail')],
  'de': [INatCommonName(languageCode: 'de', name: 'Kleine Schnecke')],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late RuntimeCommonNameRepository repository;

  Future<List<String>> stamps() async => [
    for (final row in await db.query(
      RuntimeCommonNameRepository.tableName,
      orderBy: 'entity_key, language_code',
    ))
      '${row['entity_key']}/${row['language_code']}=${row['inat_taxon_id']}',
  ];

  setUp(() async {
    db = await openInMemoryUserDatabase();
    repository = RuntimeCommonNameRepository(
      searchRepository: RuntimeCommonNameSearchRepository(database: db),
      database: db,
    );
  });

  tearDown(() => db.close());

  test('species names carry the taxon they were fetched from', () async {
    await repository.saveSpeciesCommonNamesBatch({
      _species: (taxonId: 7, commonNames: _names),
    });

    expect(await stamps(), ['species:sp1/de=7', 'species:sp1/en=7']);
  });

  test(
    'names of a higher taxon carry the taxon they were fetched from',
    () async {
      await repository.saveTaxonomyCommonNamesBatch([
        const RuntimeTaxonomyCommonNameRecord(
          entityKey: 'genus:triphora',
          entityType: 'genera',
          scientificName: 'Triphora',
          referenceCommonNames: {},
          taxonId: 8,
          runtimeCommonNames: _names,
        ),
      ]);

      expect(await stamps(), ['genus:triphora/de=8', 'genus:triphora/en=8']);
    },
  );

  test(
    'a no-result marker carries the taxon that had no names, or none',
    () async {
      await repository.markNoCommonNames(
        entityKey: 'species:sp1',
        entityType: 'species',
        taxonId: 9,
      );
      await repository.markNoCommonNames(
        entityKey: 'genus:triphora',
        entityType: 'genera',
        taxonId: null,
      );

      expect(await stamps(), [
        'genus:triphora/${RuntimeCommonNameRepository.noResultLanguageCode}=null',
        'species:sp1/${RuntimeCommonNameRepository.noResultLanguageCode}=9',
      ]);
    },
  );
}
