import 'dart:io';

import 'package:discere/app/bootstrap/inat_provenance_step.dart';
import 'package:discere/enrichment/pipeline/service/inat_provenance_reconciler.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bootstrap_harness.dart';

/// A species the fixture has no iNat id for: photos stamped with any taxon
/// do not belong to it.
const _unmappedSpeciesId = 'discere:species:unmapped';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory supportDir;

  Future<void> addStampedPhotos() async {
    await (await DatabaseHelper.userDb).insert('inat_photo_cache', {
      'species_id': _unmappedSpeciesId,
      'photo_url': 'https://inat/photo',
      'fetched_at': 1,
      'inat_taxon_id': 5,
    });
  }

  Future<int> photoRows() async =>
      (await (await DatabaseHelper.userDb).query('inat_photo_cache')).length;

  Future<int?> reconciledVersion() async =>
      (await SharedPreferences.getInstance()).getInt(
        INatProvenanceReconciler.prefKeyReconciledVersion,
      );

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('provenance_step_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          return supportDir.path;
        });
    await seedDatabases(supportDir);
    SharedPreferences.setMockInitialValues({
      ...installedPreferences(version: 2),
      ReferenceIdMigration.prefKeyAppliedVersion: 2,
    });
  });

  tearDown(() async {
    await DatabaseHelper.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await supportDir.delete(recursive: true);
  });

  test('reconciles once per installed reference database', () async {
    await addStampedPhotos();

    await reconcileINatProvenance();
    expect(await photoRows(), 0);
    expect(await reconciledVersion(), 2);

    await addStampedPhotos();
    await reconcileINatProvenance();
    expect(await photoRows(), 1);
  });

  test('a failure lets the start go on and leaves the version to the next '
      'start', () async {
    await addStampedPhotos();
    await (await DatabaseHelper.userDb).execute(
      'CREATE TRIGGER fail_photos BEFORE DELETE ON inat_photo_cache '
      "BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );

    await reconcileINatProvenance();

    expect(await photoRows(), 1);
    expect(await reconciledVersion(), isNull);
  });

  test('waits until the reference IDs are applied for the installed '
      'database', () async {
    await (await SharedPreferences.getInstance()).setInt(
      ReferenceIdMigration.prefKeyAppliedVersion,
      1,
    );
    await addStampedPhotos();

    await reconcileINatProvenance();

    expect(await photoRows(), 1);
    expect(await reconciledVersion(), isNull);
  });
}
