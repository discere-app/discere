import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/repository/common_name_repository.dart';
import 'package:discere/catalog/repository/taxonomy_common_name_enricher.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'runtime_common_names_test_schema.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database userDb;
  late TaxonomyCommonNameEnricher enricher;

  setUp(() async {
    userDb = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await createRuntimeCommonNamesTable(userDb);
    enricher = TaxonomyCommonNameEnricher(
      const CommonNameRepository(),
      userDatabase: () async => userDb,
    );
  });

  tearDown(() => userDb.close());

  Future<void> insertRuntimeName(
    String entityKey,
    String languageCode,
    String name,
  ) {
    return userDb.insert('runtime_common_names', {
      'entity_key': entityKey,
      'entity_type': entityKey.split(':').first,
      'language_code': languageCode,
      'name': name,
      'position': 0,
      'fetched_at': 0,
    });
  }

  final genus = SearchResult(
    id: 'genus-1',
    name: 'Carcharodon',
    commonNames: const {
      Language.en: ['White sharks'],
    },
    type: SearchEntityType.genus,
  );

  TaxonomyDetail genusDetail() => TaxonomyDetail(
    result: genus,
    commonNames: genus.commonNames,
    classification: const [
      TaxonomyClassificationEntry(
        label: TaxonomyRankLabel.family,
        id: 'family-1',
        scientificName: 'Lamnidae',
        commonNames: {
          Language.en: ['Mackerel sharks'],
        },
      ),
      TaxonomyClassificationEntry(
        label: TaxonomyRankLabel.classType,
        id: 'class-1',
        scientificName: 'Chondrichthyes',
        commonNames: {
          Language.en: ['Cartilaginous fishes'],
        },
      ),
      TaxonomyClassificationEntry(
        label: TaxonomyRankLabel.superClass,
        scientificName: 'Vertebrata',
      ),
    ],
    metrics: const [TaxonomyMetric(type: TaxonomyMetricType.species, count: 3)],
    attributes: const [TaxonomyAttribute(key: 'subfamily', value: 'Testinae')],
    isReferenceBacked: true,
  );

  group('enrichDetail', () {
    test('puts fetched names ahead of the reference names, and a reference '
        'name that repeats a fetched one is dropped', () async {
      await insertRuntimeName('genus:carcharodon', 'en', 'white SHARKS');
      await insertRuntimeName('genus:carcharodon', 'en', 'Great whites');
      await insertRuntimeName('family:lamnidae', 'de', 'Makrelenhaie');

      final detail = await enricher.enrichDetail(genusDetail());

      expect(detail.commonNames[Language.en], ['white SHARKS', 'Great whites']);
      expect(detail.classification.first.commonNames, {
        Language.de: ['Makrelenhaie'],
        Language.en: ['Mackerel sharks'],
        Language.fr: <String>[],
        Language.es: <String>[],
      });
    });

    test('leaves rows without fetched names, and the superclass, as they '
        'are, and keeps everything that is not a name', () async {
      await insertRuntimeName('family:lamnidae', 'de', 'Makrelenhaie');

      final detail = await enricher.enrichDetail(genusDetail());

      final classRow = detail.classification[1];
      expect(classRow.label, TaxonomyRankLabel.classType);
      expect(classRow.id, 'class-1');
      expect(classRow.commonNames, {
        Language.en: ['Cartilaginous fishes'],
      });
      expect(detail.classification[2].commonNames, isEmpty);
      expect(detail.metrics.single.count, 3);
      expect(detail.attributes.single.value, 'Testinae');
      expect(detail.isReferenceBacked, isTrue);
    });

    test('without a user DB returns the detail untouched', () async {
      final referenceOnly = TaxonomyCommonNameEnricher(
        const CommonNameRepository(),
        userDatabase: () async => null,
      );
      await insertRuntimeName('family:lamnidae', 'de', 'Makrelenhaie');
      final detail = genusDetail();

      expect(await referenceOnly.enrichDetail(detail), same(detail));
    });
  });

  group('enrichChildren', () {
    test('keys a higher-rank child by rank and name, a species child by its '
        'id', () async {
      await insertRuntimeName('genus:carcharodon', 'de', 'Weißhaie');
      await insertRuntimeName('species:species-1', 'de', 'Weißer Hai');

      final children = await enricher.enrichChildren([
        genus,
        SearchResult(
          id: 'species-1',
          name: 'Carcharodon carcharias',
          commonNames: const {
            Language.en: ['Great white shark'],
          },
          type: SearchEntityType.species,
        ),
      ]);

      expect(children[0].commonNames[Language.de], ['Weißhaie']);
      expect(children[0].commonNames[Language.en], ['White sharks']);
      expect(children[1].id, 'species-1');
      expect(children[1].type, SearchEntityType.species);
      expect(children[1].commonNames[Language.de], ['Weißer Hai']);
      expect(children[1].commonNames[Language.en], ['Great white shark']);
    });

    test('leaves a child without fetched names as it is', () async {
      await insertRuntimeName('genus:isurus', 'de', 'Makohaie');

      final children = await enricher.enrichChildren([genus]);

      expect(children.single.commonNames, {
        Language.en: ['White sharks'],
      });
    });
  });
}
