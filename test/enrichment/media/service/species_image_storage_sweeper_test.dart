import 'dart:io';

import 'package:discere/catalog/repository/reference_picture_url_repository.dart';
import 'package:discere/enrichment/media/model/species_image_sweep_trigger.dart';
import 'package:discere/enrichment/media/repository/species_image_retention_repository.dart';
import 'package:discere/enrichment/media/service/species_image_storage_sweeper.dart';
import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/external/inaturalist/models/inat_photo.dart';
import 'package:discere/shared/service/cached_image_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/in_memory_user_database.dart';

const _needed = 'sp-needed';
const _unneeded = 'sp-unneeded';

const _external = 'external_images';
const _reference = 'reference_images';

String _photoOf(String speciesId) =>
    'https://static.inaturalist.org/photos/$speciesId/medium.jpg';

String _referencePictureOf(String speciesId) =>
    'https://www.fishbase.se/images/species/$speciesId.jpg';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documentsDir;
  late Database userDb;
  late Database referenceDb;
  late CachedImageStore store;
  late SharedPreferences preferences;
  late SpeciesImageStorageSweeper sweeper;

  Future<File> downloaded(String url, String directory, {int size = 1}) async {
    final file = File(await store.pathFor(url, storageDirectory: directory));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(size, 1));
    return file;
  }

  /// A species as enrichment leaves it: photos cached with what came with
  /// them, every capability done, and its files on disk.
  Future<void> enriched(String speciesId) async {
    await INatPhotoCacheRepository(database: userDb).cachePhotos(speciesId, [
      INatPhoto(
        url: 'https://static.inaturalist.org/photos/$speciesId/square.jpg',
        attribution: 'someone',
        licenseCode: 'cc-by',
      ),
    ], taxonId: 7);
    for (final provider in ['wikipedia', 'iucnStatus', 'inaturalist']) {
      await userDb.insert('external_identifier_cache', {
        'entity_id': speciesId,
        'provider': provider,
        'external_id': '$provider-of-$speciesId',
        'last_synced_at': 1,
      });
    }
    for (final capability in EnrichmentCapability.values) {
      await userDb.insert('enrichment_species_capability_state', {
        'species_id': speciesId,
        'capability': capability.wireName,
        'state': 'done',
        'reference_db_version': 2,
        'updated_at': 1,
      });
    }
    await referenceDb.insert('pictures', {
      'species': speciesId,
      'url': _referencePictureOf(speciesId),
      'is_usable': 1,
    });
  }

  Future<Set<String>> capabilitiesOf(String speciesId) async => {
    for (final row in await userDb.query(
      'enrichment_species_capability_state',
      where: 'species_id = ?',
      whereArgs: [speciesId],
    ))
      row['capability'] as String,
  };

  Future<Set<String>> cachedProvidersOf(String speciesId) async => {
    for (final row in await userDb.query(
      'external_identifier_cache',
      where: 'entity_id = ?',
      whereArgs: [speciesId],
    ))
      row['provider'] as String,
  };

  setUp(() async {
    documentsDir = await Directory.systemTemp.createTemp('image_sweeper');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          return documentsDir.path;
        });
    userDb = await openInMemoryUserDatabase();
    referenceDb = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await referenceDb.execute(
      'CREATE TABLE pictures (species TEXT, url TEXT, is_usable INTEGER)',
    );
    store = CachedImageStore();
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    sweeper = SpeciesImageStorageSweeper(
      retention: SpeciesImageRetentionRepository(database: userDb),
      photoCache: INatPhotoCacheRepository(database: userDb),
      referencePictures: ReferencePictureUrlRepository(database: referenceDb),
      store: store,
      preferences: preferences,
    );
    await enriched(_needed);
    await enriched(_unneeded);
  });

  tearDown(() async {
    await userDb.close();
    await referenceDb.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await documentsDir.delete(recursive: true);
  });

  group('a species no longer needed', () {
    test('loses its photos with what came with them, and the work that '
        'fetched its images', () async {
      await sweeper.sweepIfNeeded(
        neededSpeciesIds: {_needed},
        installedVersion: 3,
      );

      expect(
        await INatPhotoCacheRepository(
          database: userDb,
        ).getCachedPhotosForSpecies({_needed, _unneeded}),
        {_needed: hasLength(1)},
      );
      expect(await cachedProvidersOf(_unneeded), {'inaturalist'});
      // Its names stay, and so does the row saying they are there.
      expect(await capabilitiesOf(_unneeded), {'speciesCommonNames'});
    });

    test('loses its files in both directories', () async {
      final photo = await downloaded(_photoOf(_unneeded), _external);
      final picture = await downloaded(
        _referencePictureOf(_unneeded),
        _reference,
      );

      await sweeper.sweepIfNeeded(
        neededSpeciesIds: {_needed},
        installedVersion: 3,
      );

      expect(await photo.exists(), isFalse);
      expect(await picture.exists(), isFalse);
    });
  });

  test('a needed species keeps its rows and its files', () async {
    final photo = await downloaded(_photoOf(_needed), _external);
    final picture = await downloaded(_referencePictureOf(_needed), _reference);

    await sweeper.sweepIfNeeded(
      neededSpeciesIds: {_needed},
      installedVersion: 3,
    );

    expect(
      await INatPhotoCacheRepository(database: userDb).getCachedPhotos(_needed),
      hasLength(1),
    );
    expect(await cachedProvidersOf(_needed), {
      'wikipedia',
      'iucnStatus',
      'inaturalist',
    });
    expect(await capabilitiesOf(_needed), {
      for (final capability in EnrichmentCapability.values) capability.wireName,
    });
    expect(await photo.exists(), isTrue);
    expect(await picture.exists(), isTrue);
  });

  test('an iNat image stored with the reference images stays while its '
      'photo is cached', () async {
    final kept = await downloaded(_photoOf(_needed), _reference);
    final released = await downloaded(_photoOf(_unneeded), _reference);

    await sweeper.sweepIfNeeded(
      neededSpeciesIds: {_needed},
      installedVersion: 3,
    );

    expect(await kept.exists(), isTrue);
    expect(await released.exists(), isFalse);
  });

  group('sweeps again', () {
    late File orphan;

    setUp(() async {
      await sweeper.sweepIfNeeded(
        neededSpeciesIds: {_needed, 'sp-also-needed'},
        installedVersion: 3,
      );
      orphan = await downloaded('https://example.org/orphan.jpg', _external);
    });

    test('not while neither the needed species nor the version '
        'changed', () async {
      // Nothing is read for a sweep that does not run: without the tables,
      // a read would throw.
      await userDb.execute('DROP TABLE inat_photo_cache');
      await referenceDb.execute('DROP TABLE pictures');

      await sweeper.sweepIfNeeded(
        // Another order of the same species is no change.
        neededSpeciesIds: {'sp-also-needed', _needed},
        installedVersion: 3,
      );

      expect(await orphan.exists(), isTrue);
    });

    test('once the needed species changed', () async {
      await sweeper.sweepIfNeeded(
        neededSpeciesIds: {_needed},
        installedVersion: 3,
      );

      expect(await orphan.exists(), isFalse);
    });

    test('for a newer reference database', () async {
      await sweeper.sweepIfNeeded(
        neededSpeciesIds: {_needed, 'sp-also-needed'},
        installedVersion: 4,
      );

      expect(await orphan.exists(), isFalse);
      expect(
        SpeciesImageStorageSweeper.lastSweep(preferences)?.trigger,
        SpeciesImageSweepTrigger.automatic,
      );
    });

    test('when asked to, and then not again', () async {
      await SpeciesImageStorageSweeper.requestSweep(preferences);

      await sweeper.sweepIfNeeded(
        neededSpeciesIds: {_needed, 'sp-also-needed'},
        installedVersion: 3,
      );

      expect(await orphan.exists(), isFalse);
      expect(
        SpeciesImageStorageSweeper.lastSweep(preferences)?.trigger,
        SpeciesImageSweepTrigger.manual,
      );
      expect(
        preferences.getBool(SpeciesImageStorageSweeper.prefKeySweepRequested),
        isNull,
      );
    });
  });

  group('when a set to keep cannot be read', () {
    late File photo;
    late File picture;

    setUp(() async {
      photo = await downloaded(_photoOf(_needed), _external);
      picture = await downloaded(_referencePictureOf(_needed), _reference);
      await SpeciesImageStorageSweeper.requestSweep(preferences);
    });

    Future<void> expectNothingChanged(Object? error) async {
      // An unreadable set must never pass for an empty one, which would
      // delete every image.
      expect(await capabilitiesOf(_unneeded), hasLength(4));
      expect(await cachedProvidersOf(_unneeded), hasLength(3));
      expect(await photo.exists(), isTrue);
      expect(await picture.exists(), isTrue);
      expect(
        preferences.getString(SpeciesImageStorageSweeper.prefKeyFingerprint),
        isNull,
      );
      expect(
        preferences.getBool(SpeciesImageStorageSweeper.prefKeySweepRequested),
        isTrue,
      );
      expect(SpeciesImageStorageSweeper.lastSweep(preferences), isNull);
      expect(error, isA<DatabaseException>());
    }

    Future<Object?> sweepCatching() async {
      try {
        await sweeper.sweepIfNeeded(
          neededSpeciesIds: {_needed},
          installedVersion: 3,
        );
      } catch (e) {
        return e;
      }
      return null;
    }

    test('the reference pictures, nothing is let go or deleted', () async {
      await referenceDb.execute('DROP TABLE pictures');

      await expectNothingChanged(await sweepCatching());
    });

    test('the cached photos, nothing is let go or deleted', () async {
      await userDb.execute('DROP TABLE inat_photo_cache');

      await expectNothingChanged(await sweepCatching());
    });
  });

  group('the result', () {
    test('is recorded with what the sweep deleted', () async {
      await downloaded(_photoOf(_unneeded), _external, size: 300);
      await downloaded(_photoOf(_unneeded), _reference, size: 7);
      await downloaded(_referencePictureOf(_unneeded), _reference, size: 50);
      await downloaded(_referencePictureOf(_needed), _reference, size: 1000);

      await sweeper.sweepIfNeeded(
        neededSpeciesIds: {_needed, 'sp-without-images'},
        installedVersion: 3,
      );

      final sweep = SpeciesImageStorageSweeper.lastSweep(preferences)!;
      expect(sweep.trigger, SpeciesImageSweepTrigger.automatic);
      expect(sweep.neededSpeciesCount, 2);
      expect(sweep.releasedSpeciesCount, 1);
      expect(
        {
          for (final MapEntry(:key, :value) in sweep.directories.entries)
            key: (value.deletedFiles, value.freedBytes),
        },
        {_external: (1, 300), _reference: (2, 57)},
      );
    });

    test('reads as none when it cannot be read', () async {
      await preferences.setString(
        SpeciesImageStorageSweeper.prefKeyLastSweep,
        '{"sweptAt": 1}',
      );

      expect(SpeciesImageStorageSweeper.lastSweep(preferences), isNull);
    });
  });
}
