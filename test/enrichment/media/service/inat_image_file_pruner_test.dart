import 'dart:io';

import 'package:discere/enrichment/media/service/inat_image_file_pruner.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/external/inaturalist/models/inat_photo.dart';
import 'package:discere/shared/service/cached_image_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

const _cachedUrl = 'https://static.inaturalist.org/photos/1/medium.jpg';
const _orphanedUrl = 'https://static.inaturalist.org/photos/2/medium.jpg';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documentsDir;
  late Database database;
  late CachedImageStore store;
  late SharedPreferences preferences;
  late INatImageFilePruner pruner;

  Future<File> downloaded(String url) async {
    final file = File(
      await store.pathFor(url, storageDirectory: 'external_images'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1]);
    return file;
  }

  setUp(() async {
    documentsDir = await Directory.systemTemp.createTemp('inat_image_pruner');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          return documentsDir.path;
        });
    database = await openInMemoryUserDatabase();
    await INatPhotoCacheRepository(database: database).cachePhotos('sp1', [
      INatPhoto(
        url: 'https://static.inaturalist.org/photos/1/square.jpg',
        attribution: 'someone',
        licenseCode: 'cc-by',
      ),
    ], taxonId: 7);
    store = CachedImageStore();
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    pruner = INatImageFilePruner(
      photoCache: INatPhotoCacheRepository(database: database),
      store: store,
      preferences: preferences,
    );
  });

  tearDown(() async {
    await database.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await documentsDir.delete(recursive: true);
  });

  test('deletes the files no cached photo names, and records the '
      'version', () async {
    final cached = await downloaded(_cachedUrl);
    final orphaned = await downloaded(_orphanedUrl);

    await pruner.pruneIfNeeded(installedVersion: 3);

    expect(await cached.exists(), isTrue);
    expect(await orphaned.exists(), isFalse);
    expect(preferences.getInt(INatImageFilePruner.prefKeyPrunedVersion), 3);
  });

  test('prunes once per installed reference database', () async {
    await preferences.setInt(INatImageFilePruner.prefKeyPrunedVersion, 3);
    final orphaned = await downloaded(_orphanedUrl);
    // Nothing is read for a version already pruned: without the table, a
    // read would throw.
    await database.execute('DROP TABLE inat_photo_cache');

    await pruner.pruneIfNeeded(installedVersion: 3);

    expect(await orphaned.exists(), isTrue);
  });

  test('deletes nothing and records no version when the cached photos '
      'cannot be read', () async {
    final cached = await downloaded(_cachedUrl);
    await database.execute('DROP TABLE inat_photo_cache');

    Object? error;
    try {
      await pruner.pruneIfNeeded(installedVersion: 3);
    } catch (e) {
      error = e;
    }

    // An unreadable cache must never pass for an empty one, which would
    // delete every image.
    expect(await cached.exists(), isTrue);
    expect(
      preferences.getInt(INatImageFilePruner.prefKeyPrunedVersion),
      isNull,
    );
    expect(error, isA<DatabaseException>());
  });
}
