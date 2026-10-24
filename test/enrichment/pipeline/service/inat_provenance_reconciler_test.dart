import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_rejection_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/inat_allowed_ancestor_repository.dart';
import 'package:discere/enrichment/pipeline/repository/inat_provenance_repository.dart';
import 'package:discere/enrichment/pipeline/service/higher_taxon_id_resolver.dart';
import 'package:discere/enrichment/pipeline/service/inat_provenance_reconciler.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/external/inaturalist/inat_api_client.dart';
import 'package:discere/external/inaturalist/inat_taxon_details.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../mocks.mocks.dart';
import '../../../support/in_memory_user_database.dart';

const _version = 3;

Species _species(String id) => Species(
  id,
  id,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database userDb;
  late Database referenceDb;
  late SharedPreferences preferences;

  INatProvenanceReconciler reconciler() => INatProvenanceReconciler(
    provenance: INatProvenanceRepository(database: userDb),
    referenceIds: ExternalIdRepository(referenceDatabase: referenceDb),
    rejections: ExternalIdRejectionRepository(referenceDatabase: referenceDb),
    preferences: preferences,
  );

  Future<void> mapInReference(String entityId, int taxonId) =>
      referenceDb.insert('entity_external_ids', {
        'entity_id': entityId,
        'provider': 'inaturalist',
        'external_id': '$taxonId',
      });

  Future<void> rejectInReference(String entityId) =>
      referenceDb.insert('entity_external_id_rejections', {
        'entity_id': entityId,
        'entity_type': 'species',
        'provider': 'inaturalist',
        'reason': 'phylum_mismatch',
      });

  Future<void> cacheTaxonId(String entityId, int taxonId) =>
      userDb.insert('external_identifier_cache', {
        'entity_id': entityId,
        'provider': 'inaturalist',
        'external_id': '$taxonId',
        'last_synced_at': 1,
      });

  Future<void> addPhotos(String speciesId, {int? stamp}) =>
      userDb.insert('inat_photo_cache', {
        'species_id': speciesId,
        'photo_url': 'https://inat/$speciesId',
        'fetched_at': 1,
        'inat_taxon_id': stamp,
      });

  Future<void> addNames(String entityKey, {int? stamp}) =>
      userDb.insert('runtime_common_names', {
        'entity_key': entityKey,
        'entity_type': 'species',
        'language_code': 'en',
        'name': 'Name of $entityKey',
        'fetched_at': 1,
        'inat_taxon_id': stamp,
      });

  Future<Map<String, int?>> photoStamps() =>
      INatProvenanceRepository(database: userDb).photoStamps();

  Future<Map<String, int?>> nameStamps() =>
      INatProvenanceRepository(database: userDb).nameStamps();

  Future<Map<String, int>> cachedTaxonIds() =>
      INatProvenanceRepository(database: userDb).cachedTaxonIds();

  setUp(() async {
    userDb = await openInMemoryUserDatabase();
    referenceDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await referenceDb.execute(
      'CREATE TABLE entity_external_ids '
      '(entity_id TEXT, provider TEXT, external_id TEXT)',
    );
    await referenceDb.execute(
      'CREATE TABLE entity_external_id_rejections '
      '(entity_id TEXT, entity_type TEXT, provider TEXT, reason TEXT)',
    );
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await userDb.close();
    await referenceDb.close();
  });

  group('on the first run', () {
    test('stamps what the reference database explains and discards what only '
        'the old search does', () async {
      await mapInReference('sp:mapped', 10);
      await addPhotos('sp:mapped');
      await addNames('species:sp:mapped');
      await cacheTaxonId('sp:mapped', 10);
      await addPhotos('sp:searched');
      await addNames('species:sp:searched');
      await cacheTaxonId('sp:searched', 20);
      await cacheTaxonId('genus:triphora', 30);

      await reconciler().reconcileIfNeeded(installedVersion: _version);

      expect(await photoStamps(), {'sp:mapped': 10});
      expect(await nameStamps(), {'sp:mapped': 10});
      expect(await cachedTaxonIds(), isEmpty);
      expect(
        preferences.getInt(INatProvenanceReconciler.prefKeyReconciledVersion),
        _version,
      );
    });
  });

  group('after a reference-database update', () {
    setUp(() async {
      await preferences.setInt(
        INatProvenanceReconciler.prefKeyReconciledVersion,
        _version - 1,
      );
    });

    test('discards the data of species whose taxon changed, went or was '
        'rejected, and keeps the rest', () async {
      await mapInReference('sp:same', 10);
      await addPhotos('sp:same', stamp: 10);
      await mapInReference('sp:changed', 12);
      await addPhotos('sp:changed', stamp: 11);
      await addPhotos('sp:dropped', stamp: 13);
      await rejectInReference('sp:rejected');
      await cacheTaxonId('sp:rejected', 14);
      await addNames('species:sp:rejected', stamp: 14);
      await cacheTaxonId('sp:searched', 15);
      await addNames('species:sp:searched', stamp: 15);

      await reconciler().reconcileIfNeeded(installedVersion: _version);

      expect(await photoStamps(), {'sp:same': 10});
      expect(await nameStamps(), {'sp:searched': 15});
      expect(await cachedTaxonIds(), {'sp:searched': 15});
    });

    test('keeps exactly the data the resolvers would fetch again', () async {
      final cache = ExternalIdCacheRepository(database: userDb);
      final referenceIds = ExternalIdRepository(referenceDatabase: referenceDb);
      final rejections = ExternalIdRejectionRepository(
        referenceDatabase: referenceDb,
      );
      final allowedAncestors = INatAllowedAncestorRepository(
        referenceDatabase: referenceDb,
      );
      final speciesResolver = INatTaxonResolver(
        MockSpeciesRepository(),
        referenceIds,
        cache,
        rejections,
        allowedAncestors,
        MockINatTaxonIdResolver(),
      );
      final higherResolver = HigherTaxonIdResolver(
        referenceIds,
        cache,
        rejections,
        allowedAncestors,
        speciesResolver,
        INatTaxonDetails(
          api: INatApiClient(
            client: MockClient((_) async => http.Response('', 500)),
          ),
        ),
        MockINatTaxonIdResolver(),
      );
      // Every combination of reference id, cached id and rejection, each
      // with data stamped 1.
      final entities = <String>[];
      for (final referenceId in [null, 1, 2]) {
        for (final cachedId in [null, 1, 2]) {
          for (final rejected in [false, true]) {
            if (rejected && referenceId != null) continue;
            final speciesId = 'sp:$referenceId:$cachedId:$rejected';
            final genusKey = 'genus:g$referenceId$cachedId$rejected';
            for (final entityId in [speciesId, genusKey]) {
              entities.add(entityId);
              if (referenceId != null) {
                await mapInReference(entityId, referenceId);
              }
              if (cachedId != null) await cacheTaxonId(entityId, cachedId);
              if (rejected) await rejectInReference(entityId);
            }
            await addPhotos(speciesId, stamp: 1);
            await addNames(genusKey, stamp: 1);
          }
        }
      }

      await reconciler().reconcileIfNeeded(installedVersion: _version);

      final kept = {...await photoStamps(), ...await nameStamps()};
      for (final entityId in entities) {
        final knownTaxonId = entityId.startsWith('genus:')
            ? await higherResolver.knownTaxonId(entityId)
            : await speciesResolver.knownTaxonId(_species(entityId));
        expect(
          kept.containsKey(entityId),
          knownTaxonId == 1,
          reason: '$entityId: resolvers know $knownTaxonId',
        );
      }
      expect(kept, isNotEmpty);
    });
  });

  test('runs once per reference-database version', () async {
    await reconciler().reconcileIfNeeded(installedVersion: _version);
    await addPhotos('sp:fetched-later', stamp: 10);

    await reconciler().reconcileIfNeeded(installedVersion: _version);

    expect(await photoStamps(), {'sp:fetched-later': 10});
  });

  test('records nothing when applying the plan fails', () async {
    await mapInReference('sp:changed', 12);
    await addPhotos('sp:changed', stamp: 11);
    await userDb.execute(
      'CREATE TRIGGER fail_photos BEFORE DELETE ON inat_photo_cache '
      "BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );

    await expectLater(
      reconciler().reconcileIfNeeded(installedVersion: _version),
      throwsA(isA<DatabaseException>()),
    );

    expect(
      preferences.getInt(INatProvenanceReconciler.prefKeyReconciledVersion),
      isNull,
    );
    expect(await photoStamps(), {'sp:changed': 11});
  });
}
