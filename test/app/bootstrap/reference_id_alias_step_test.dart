import 'dart:io';

import 'package:discere/app/bootstrap/reference_id_alias_step.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration_run.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'bootstrap_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final failedAt = DateTime(2026, 10, 15, 9, 30);
  late Directory supportDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('alias_step_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          return supportDir.path;
        });
    await seedDatabases(supportDir);
  });

  tearDown(() async {
    await DatabaseHelper.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await supportDir.delete(recursive: true);
  });

  test('a failed run is recorded as the last run, replacing an earlier '
      'success, and the version is not marked applied', () async {
    // A card under an aliased ID whose rewrite the database refuses.
    final userDb = await databaseFactoryFfi.openDatabase(
      p.join(supportDir.path, 'discere_user.db'),
    );
    await userDb.insert('decks', {'id': 'd1', 'name': 'd1'});
    await userDb.insert('flashcard_stats', {
      'species_id': oldSpeciesId,
      'deck_id': 'd1',
    });
    await userDb.execute(
      'CREATE TRIGGER fail_stats BEFORE UPDATE ON flashcard_stats '
      "BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );
    await userDb.close();
    SharedPreferences.setMockInitialValues({
      ...installedPreferences(version: 2),
      ReferenceIdMigration.prefKeyAppliedVersion: 1,
    });
    final preferences = await SharedPreferences.getInstance();
    await ReferenceIdMigrationSucceeded(
      referenceDbVersion: 1,
      ranAt: DateTime(2026),
      referencedIdCount: 0,
      aliasCount: 0,
      targets: const {},
    ).save(preferences);

    await applyReferenceIdAliases(now: () => failedAt);

    final run = ReferenceIdMigrationRun.read(preferences);
    expect(run, isA<ReferenceIdMigrationFailed>());
    expect(run!.referenceDbVersion, 2);
    expect(run.ranAt, failedAt);
    expect(preferences.getInt(ReferenceIdMigration.prefKeyAppliedVersion), 1);
  });

  test('a start without a stamped version records no run', () async {
    SharedPreferences.setMockInitialValues({});

    await applyReferenceIdAliases(now: () => failedAt);

    expect(
      ReferenceIdMigrationRun.read(await SharedPreferences.getInstance()),
      isNull,
    );
  });
}
