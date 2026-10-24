import 'package:discere/catalog/repository/runtime_common_name_search_repository.dart';
import 'package:discere/enrichment/pipeline/repository/inat_provenance_planner.dart';
import 'package:discere/enrichment/pipeline/repository/inat_provenance_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

const _discarded = 'discere:species:1';
const _bystander = 'discere:species:2';

/// A plan that discards everything of [_discarded] and of `genus:x`, and
/// touches nothing else.
const _discardPlan = INatProvenancePlan(
  photosToStamp: {},
  photosToDiscard: {_discarded},
  namesToStamp: {},
  namesToDiscard: {_discarded, 'genus:x'},
  cachedTaxonIdsToDrop: {_discarded},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late INatProvenanceRepository repository;

  Future<void> addPhotos(String speciesId, {int? stamp}) async {
    for (final url in [
      'https://inat/$speciesId/a',
      'https://inat/$speciesId/b',
    ]) {
      await db.insert('inat_photo_cache', {
        'species_id': speciesId,
        'photo_url': url,
        'fetched_at': 1,
        'inat_taxon_id': stamp,
      });
    }
  }

  Future<void> addNames(String entityKey, String name, {int? stamp}) async {
    await db.insert('runtime_common_names', {
      'entity_key': entityKey,
      'entity_type': entityKey.startsWith('genus:') ? 'genera' : 'species',
      'language_code': 'en',
      'name': name,
      'fetched_at': 1,
      'inat_taxon_id': stamp,
    });
    await RuntimeCommonNameSearchRepository(database: db).upsertDocument(
      RuntimeCommonNameSearchDocument(
        entityKey: entityKey,
        entityId: entityKey,
        entityType: 'species',
        scientificName: entityKey,
        commonNameEn: name,
      ),
    );
  }

  Future<void> addCachedIds(String entityId) async {
    for (final (provider, value) in [
      ('inaturalist', '10'),
      ('wikipedia', 'https://en.wikipedia.org/wiki/X'),
      ('iucnStatus', 'lc'),
    ]) {
      await db.insert('external_identifier_cache', {
        'entity_id': entityId,
        'provider': provider,
        'external_id': value,
        'last_synced_at': 1,
      });
    }
  }

  Future<void> addCapabilities(String speciesId) async {
    for (final capability in [
      'base',
      'inatPrimary',
      'inatBackfill',
      'speciesCommonNames',
    ]) {
      await db.insert('enrichment_species_capability_state', {
        'species_id': speciesId,
        'capability': capability,
        'state': 'done',
        'attempt_count': 2,
        'last_error': 'earlier',
        'updated_at': 1,
      });
    }
  }

  Future<void> addTaxonomyWork(String entityKey) =>
      db.insert('enrichment_taxonomy_work', {
        'work_key': '$entityKey:work',
        'runtime_entity_key': entityKey,
        'common_names_state': 'done',
        'attempt_count': 2,
        'updated_at': 1,
      });

  Future<List<String>> rows(String table, String key, {String? where}) async {
    final result = await db.query(table, where: where, orderBy: key);
    return [for (final row in result) row.values.join('|')];
  }

  /// Every row the plan must not touch, in a comparable form.
  Future<List<String>> bystanderRows() async => [
    ...await rows(
      'inat_photo_cache',
      'photo_url',
      where: "species_id = '$_bystander'",
    ),
    ...await rows(
      'runtime_common_names',
      'name',
      where: "entity_key IN ('species:$_bystander', 'genus:y')",
    ),
    ...await rows(
      'runtime_common_name_search_documents',
      'entity_key',
      where: "entity_key IN ('species:$_bystander', 'genus:y')",
    ),
    ...await rows(
      'external_identifier_cache',
      'provider',
      where: "entity_id = '$_bystander'",
    ),
    ...await rows(
      'enrichment_species_capability_state',
      'capability',
      where: "species_id = '$_bystander' OR capability = 'base'",
    ),
    ...await rows(
      'enrichment_taxonomy_work',
      'work_key',
      where: "runtime_entity_key = 'genus:y'",
    ),
  ];

  Future<Set<int>> ftsRowIds() async => {
    for (final row in await db.rawQuery(
      'SELECT rowid FROM runtime_common_name_search_fts',
    ))
      row['rowid'] as int,
  };

  Future<Set<int>> documentRowIds() async => {
    for (final row in await db.rawQuery(
      'SELECT rowid FROM runtime_common_name_search_documents',
    ))
      row['rowid'] as int,
  };

  setUp(() async {
    db = await openInMemoryUserDatabase();
    repository = INatProvenanceRepository(database: db);
  });

  tearDown(() => db.close());

  group('reads', () {
    test('the stamps of photos and names, keyed by entity id', () async {
      await addPhotos(_discarded, stamp: 10);
      await addPhotos(_bystander);
      await addNames('species:$_discarded', 'Snail', stamp: 10);
      await addNames('genus:x', 'Worms');

      expect(await repository.photoStamps(), {
        _discarded: 10,
        _bystander: null,
      });
      expect(await repository.nameStamps(), {_discarded: 10, 'genus:x': null});
    });

    test('the cached iNat ids, leaving out what does not parse', () async {
      await addCachedIds(_discarded);
      await db.insert('external_identifier_cache', {
        'entity_id': 'genus:x',
        'provider': 'inaturalist',
        'external_id': 'not-an-id',
        'last_synced_at': 1,
      });

      expect(await repository.cachedTaxonIds(), {_discarded: 10});
    });
  });

  group('discarding', () {
    setUp(() async {
      for (final speciesId in [_discarded, _bystander]) {
        await addPhotos(speciesId, stamp: 10);
        await addNames('species:$speciesId', 'Snail $speciesId', stamp: 10);
        await addCachedIds(speciesId);
        await addCapabilities(speciesId);
      }
      for (final genus in ['genus:x', 'genus:y']) {
        await addNames(genus, 'Worms $genus', stamp: 20);
        await addTaxonomyWork(genus);
      }
    });

    test('leaves everything else as it was', () async {
      final before = await bystanderRows();

      await repository.apply(_discardPlan);

      expect(await bystanderRows(), before);
      expect(before, hasLength(15));
    });

    test('takes the photos with their Wikipedia link and IUCN status, and '
        'the cached iNat id', () async {
      await repository.apply(_discardPlan);

      expect(
        await rows(
          'inat_photo_cache',
          'photo_url',
          where: "species_id = '$_discarded'",
        ),
        isEmpty,
      );
      expect(
        await rows(
          'external_identifier_cache',
          'provider',
          where: "entity_id = '$_discarded'",
        ),
        isEmpty,
      );
    });

    test('takes the names and their search documents, full-text rows '
        'included', () async {
      final bystanderDocuments = await documentRowIds();

      await repository.apply(_discardPlan);

      expect(
        await rows(
          'runtime_common_names',
          'name',
          where: "entity_key IN ('species:$_discarded', 'genus:x')",
        ),
        isEmpty,
      );
      final documents = await documentRowIds();
      expect(documents, hasLength(bystanderDocuments.length - 2));
      expect(await ftsRowIds(), documents);
    });

    test('resets the iNat work of what it discarded to pending, keeping the '
        'rows', () async {
      await repository.apply(_discardPlan);

      final capabilities = await db.query(
        'enrichment_species_capability_state',
        where: "species_id = '$_discarded'",
        orderBy: 'capability',
      );
      expect(
        [
          for (final row in capabilities)
            '${row['capability']}=${row['state']}/${row['attempt_count']}/'
                '${row['last_error']}',
        ],
        [
          'base=done/2/earlier',
          'inatBackfill=pending/0/null',
          'inatPrimary=pending/0/null',
          'speciesCommonNames=pending/0/null',
        ],
      );
      final work = await db.query(
        'enrichment_taxonomy_work',
        where: "runtime_entity_key = 'genus:x'",
      );
      expect(work.single['common_names_state'], 'pending');
      expect(work.single['attempt_count'], 0);
    });
  });

  test('stamps photos and names without touching anything else', () async {
    await addPhotos(_discarded);
    await addNames('species:$_discarded', 'Snail');
    await addNames('genus:x', 'Worms');
    await addPhotos(_bystander);

    await repository.apply(
      const INatProvenancePlan(
        photosToStamp: {_discarded: 10},
        photosToDiscard: {},
        namesToStamp: {_discarded: 10, 'genus:x': 20},
        namesToDiscard: {},
        cachedTaxonIdsToDrop: {},
      ),
    );

    expect(await repository.photoStamps(), {_discarded: 10, _bystander: null});
    expect(await repository.nameStamps(), {_discarded: 10, 'genus:x': 20});
    expect(await documentRowIds(), hasLength(2));
  });
}
