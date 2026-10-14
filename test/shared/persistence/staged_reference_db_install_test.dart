import 'dart:io';

import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
import 'package:discere/shared/persistence/staged_reference_db.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Installing a staged reference database while something of the session
/// that just ended still holds the old file open — work that outlived the
/// restart and opened the reference database after its close. sqflite
/// keeps one connection per path, so without closing it after the rename
/// the new bootstrap would be handed that connection and read the replaced
/// file under the new version.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory supportDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('staged_install');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => supportDir.path);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({
      ReferenceDatabaseProvisioner.prefKeyVersion: 1,
      ReferenceDatabaseProvisioner.prefKeySchemaVersion: 2,
    });
  });

  tearDown(() async {
    await DatabaseHelper.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await supportDir.delete(recursive: true);
  });

  Future<void> writeDatabase(String path, String marker) async {
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)');
    await db.insert('metadata', {'key': 'marker', 'value': marker});
    await db.close();
  }

  Future<String> markerOf(Database db) async =>
      (await db.query('metadata')).single['value'] as String;

  test('after the rename the reference database reads the new file, even '
      'with a connection to the old one still open', () async {
    final activePath = await ReferenceDatabaseProvisioner.resolveLocalPath();
    await writeDatabase(activePath, 'old');
    final staging = StagedReferenceDb(activePath);
    await writeDatabase(staging.filePath, 'new');
    await staging.writeMetadata(version: 2, schemaVersion: 2);

    // The straggler: opened after the session closed its databases.
    expect(await markerOf(await DatabaseHelper.referenceDb), 'old');

    await ReferenceDatabaseProvisioner(
      downloader: ReferenceDbDownloader(
        client: MockClient((_) async => http.Response('', 503)),
        foregroundServiceKeeper: const NoopForegroundServiceKeeper(),
      ),
      networkAvailability: const AlwaysOnlineNetworkAvailability(),
      closeOpenDatabases: DatabaseHelper.close,
    ).installStagedUpdate();

    expect(await markerOf(await DatabaseHelper.referenceDb), 'new');
  });
}
