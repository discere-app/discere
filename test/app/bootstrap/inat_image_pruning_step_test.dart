import 'dart:io';

import 'package:discere/app/bootstrap/inat_image_pruning_step.dart';
import 'package:discere/enrichment/media/service/inat_image_file_pruner.dart';
import 'package:discere/enrichment/pipeline/service/inat_provenance_reconciler.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration.dart';
import 'package:discere/shared/service/cached_image_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bootstrap_harness.dart';

const _cachedUrl = 'https://static.inaturalist.org/photos/1/medium.jpg';
const _orphanedUrl = 'https://static.inaturalist.org/photos/2/medium.jpg';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory supportDir;
  late File cachedFile;
  late File orphanedFile;

  Future<File> downloaded(String url) async {
    final file = File(
      await CachedImageStore().pathFor(
        url,
        storageDirectory: 'external_images',
      ),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1]);
    return file;
  }

  Future<int?> prunedVersion() async => (await SharedPreferences.getInstance())
      .getInt(INatImageFilePruner.prefKeyPrunedVersion);

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('image_pruning_step');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          return supportDir.path;
        });
    await seedDatabases(supportDir);
    SharedPreferences.setMockInitialValues({
      ...installedPreferences(version: 2),
      ReferenceIdMigration.prefKeyAppliedVersion: 2,
      INatProvenanceReconciler.prefKeyReconciledVersion: 2,
    });
    await (await DatabaseHelper.userDb).insert('inat_photo_cache', {
      'species_id': 'discere:species:6002',
      'photo_url': _cachedUrl,
      'fetched_at': 1,
      'inat_taxon_id': 5,
    });
    cachedFile = await downloaded(_cachedUrl);
    orphanedFile = await downloaded(_orphanedUrl);
  });

  tearDown(() async {
    await DatabaseHelper.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await supportDir.delete(recursive: true);
  });

  test('deletes the image files no cached photo names', () async {
    await pruneOrphanedINatImages();

    expect(await cachedFile.exists(), isTrue);
    expect(await orphanedFile.exists(), isFalse);
    expect(await prunedVersion(), 2);
  });

  test('waits until the iNat data is reconciled with the installed '
      'database', () async {
    await (await SharedPreferences.getInstance()).setInt(
      INatProvenanceReconciler.prefKeyReconciledVersion,
      1,
    );

    await pruneOrphanedINatImages();

    expect(await orphanedFile.exists(), isTrue);
    expect(await prunedVersion(), isNull);
  });

  test('a failure lets the start go on and leaves the version to the next '
      'start', () async {
    await (await DatabaseHelper.userDb).execute('DROP TABLE inat_photo_cache');

    await pruneOrphanedINatImages();

    expect(await cachedFile.exists(), isTrue);
    expect(await orphanedFile.exists(), isTrue);
    expect(await prunedVersion(), isNull);
  });
}
