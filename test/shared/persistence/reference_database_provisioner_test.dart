import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNetworkAvailability implements NetworkAvailability {
  bool onWifi;

  _FakeNetworkAvailability({this.onWifi = true});

  @override
  bool get isOnline => true;

  @override
  Stream<bool> get onlineStatusChanges => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isOnWifi() async => onWifi;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const manifestUrl =
      'https://raw.githubusercontent.com/discere-app/discere-data/main/data/reference-db/manifest.json';
  const downloadUrl =
      'https://github.com/discere-app/discere-data/releases/download/refdb-v3/discere_reference.db.gz';

  late Directory tempDir;
  late List<int> rawDbBytes;
  late List<int> compressedBytes;
  late String checksum;

  http.Client buildMockClient({
    int manifestVersion = 3,
    int schemaVersion = ReferenceDatabaseProvisioner.supportedSchemaVersion,
    String? checksumOverride,
    void Function()? onDownloadRequested,
  }) {
    return MockClient((request) async {
      if (request.url.toString() == manifestUrl) {
        return http.Response(
          jsonEncode({
            'version': manifestVersion,
            'schemaVersion': schemaVersion,
            'url': downloadUrl,
            'sha256': checksumOverride ?? checksum,
            'compressedSizeBytes': compressedBytes.length,
          }),
          200,
        );
      }
      if (request.url.toString() == downloadUrl) {
        onDownloadRequested?.call();
        return http.Response.bytes(compressedBytes, 200);
      }
      return http.Response('not found', 404);
    });
  }

  ReferenceDatabaseProvisioner buildProvisioner({
    int manifestVersion = 3,
    int schemaVersion = ReferenceDatabaseProvisioner.supportedSchemaVersion,
    String? checksumOverride,
    void Function()? onDownloadRequested,
    bool onWifi = true,
  }) {
    return ReferenceDatabaseProvisioner(
      client: buildMockClient(
        manifestVersion: manifestVersion,
        schemaVersion: schemaVersion,
        checksumOverride: checksumOverride,
        onDownloadRequested: onDownloadRequested,
      ),
      networkAvailability: _FakeNetworkAvailability(onWifi: onWifi),
      foregroundServiceKeeper: const NoopForegroundServiceKeeper(),
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'reference_db_provisioner_test',
    );

    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'getApplicationSupportDirectory') {
            return tempDir.path;
          }
          return null;
        });

    SharedPreferences.setMockInitialValues({});

    rawDbBytes = utf8.encode('fake reference database contents');
    compressedBytes = gzip.encode(rawDbBytes);
    checksum = sha256.convert(compressedBytes).toString();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await tempDir.delete(recursive: true);
  });

  group('ReferenceDatabaseProvisioner', () {
    test('hasUsableLocalCopy reflects file presence', () async {
      final provisioner = buildProvisioner();
      expect(await provisioner.hasUsableLocalCopy(), isFalse);

      final path = await ReferenceDatabaseProvisioner.resolveLocalPath();
      await File(path).create(recursive: true);

      expect(await provisioner.hasUsableLocalCopy(), isTrue);
    });

    test('hasUsableLocalCopy treats a pre-existing file with no stored schema '
        'version as compatible and stamps it for future checks', () async {
      final provisioner = buildProvisioner();
      final path = await ReferenceDatabaseProvisioner.resolveLocalPath();
      await File(path).create(recursive: true);

      expect(await provisioner.hasUsableLocalCopy(), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(ReferenceDatabaseProvisioner.prefKeySchemaVersion),
        ReferenceDatabaseProvisioner.supportedSchemaVersion,
      );
    });

    test('hasUsableLocalCopy rejects a file installed under an older schema '
        'version, even though the file itself exists', () async {
      final provisioner = buildProvisioner();
      final path = await ReferenceDatabaseProvisioner.resolveLocalPath();
      await File(path).create(recursive: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        ReferenceDatabaseProvisioner.prefKeySchemaVersion,
        ReferenceDatabaseProvisioner.supportedSchemaVersion - 1,
      );

      expect(await provisioner.hasUsableLocalCopy(), isFalse);
    });

    test(
      'checkForUpdate + downloadAndInstall downloads, verifies checksum, '
      'decompresses and installs',
      () async {
        final provisioner = buildProvisioner();
        final progressValues = <double>[];

        final info = await provisioner.checkForUpdate();
        expect(info.version, 3);
        expect(info.compressedSizeBytes, compressedBytes.length);

        await provisioner.downloadAndInstall(
          info,
          onProgress: progressValues.add,
        );

        final path = await ReferenceDatabaseProvisioner.resolveLocalPath();
        final installed = await File(path).readAsBytes();
        expect(installed, rawDbBytes);
        expect(progressValues, isNotEmpty);
        expect(progressValues.last, 1.0);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(ReferenceDatabaseProvisioner.prefKeyVersion), 3);
        expect(
          prefs.getInt(ReferenceDatabaseProvisioner.prefKeySchemaVersion),
          ReferenceDatabaseProvisioner.supportedSchemaVersion,
        );
      },
    );

    test(
      'downloadAndInstall rethrows and does not install on checksum mismatch',
      () async {
        final provisioner = buildProvisioner(checksumOverride: 'deadbeef');
        final info = await provisioner.checkForUpdate();

        await expectLater(
          provisioner.downloadAndInstall(info, onProgress: (_) {}),
          throwsA(isA<DataFormatException>()),
        );

        expect(await provisioner.hasUsableLocalCopy(), isFalse);
      },
    );

    test(
      'ensureUpToDateInBackground skips the download when already up to date',
      () async {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 3,
        });
        var downloadRequested = false;
        final provisioner = buildProvisioner(
          onDownloadRequested: () => downloadRequested = true,
        );

        await provisioner.ensureUpToDateInBackground();

        expect(downloadRequested, isFalse);
        expect(await provisioner.hasUsableLocalCopy(), isFalse);
        expect(provisioner.pendingCellularUpdate, isNull);
      },
    );

    test(
      'ensureUpToDateInBackground downloads when a newer version is '
      'available on Wi-Fi',
      () async {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 1,
        });
        final provisioner = buildProvisioner(manifestVersion: 3, onWifi: true);

        await provisioner.ensureUpToDateInBackground();

        expect(await provisioner.hasUsableLocalCopy(), isTrue);
        expect(provisioner.pendingCellularUpdate, isNull);
      },
    );

    test(
      'ensureUpToDateInBackground defers to pendingCellularUpdate instead of '
      'downloading when off Wi-Fi',
      () async {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 1,
        });
        var downloadRequested = false;
        final provisioner = buildProvisioner(
          manifestVersion: 3,
          onWifi: false,
          onDownloadRequested: () => downloadRequested = true,
        );

        await provisioner.ensureUpToDateInBackground();

        expect(downloadRequested, isFalse);
        expect(await provisioner.hasUsableLocalCopy(), isFalse);
        expect(provisioner.pendingCellularUpdate?.version, 3);
      },
    );

    test(
      'downloadPendingCellularUpdate installs the pending update and clears it',
      () async {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 1,
        });
        final provisioner = buildProvisioner(manifestVersion: 3, onWifi: false);
        await provisioner.ensureUpToDateInBackground();
        expect(provisioner.pendingCellularUpdate, isNotNull);

        await provisioner.downloadPendingCellularUpdate();

        expect(await provisioner.hasUsableLocalCopy(), isTrue);
        expect(provisioner.pendingCellularUpdate, isNull);
      },
    );

    test('dismissPendingCellularUpdate clears the pending update without '
        'downloading', () async {
      SharedPreferences.setMockInitialValues({
        ReferenceDatabaseProvisioner.prefKeyVersion: 1,
      });
      var downloadRequested = false;
      final provisioner = buildProvisioner(
        manifestVersion: 3,
        onWifi: false,
        onDownloadRequested: () => downloadRequested = true,
      );
      await provisioner.ensureUpToDateInBackground();
      expect(provisioner.pendingCellularUpdate, isNotNull);

      provisioner.dismissPendingCellularUpdate();

      expect(provisioner.pendingCellularUpdate, isNull);
      expect(downloadRequested, isFalse);
    });

    test(
      'ensureUpToDateInBackground sets justInstalledUpdate after a silent '
      'Wi-Fi install',
      () async {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 1,
        });
        final provisioner = buildProvisioner(manifestVersion: 3, onWifi: true);

        await provisioner.ensureUpToDateInBackground();

        expect(provisioner.justInstalledUpdate?.version, 3);
      },
    );

    test(
      'ensureUpToDateInBackground does not set justInstalledUpdate when off '
      'Wi-Fi (surfaced via pendingCellularUpdate instead)',
      () async {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 1,
        });
        final provisioner = buildProvisioner(
          manifestVersion: 3,
          onWifi: false,
        );

        await provisioner.ensureUpToDateInBackground();

        expect(provisioner.justInstalledUpdate, isNull);
      },
    );

    test(
      'ensureUpToDateInBackground does not set justInstalledUpdate when '
      'already up to date',
      () async {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 3,
        });
        final provisioner = buildProvisioner(manifestVersion: 3);

        await provisioner.ensureUpToDateInBackground();

        expect(provisioner.justInstalledUpdate, isNull);
      },
    );

    test(
      'dismissJustInstalledUpdate clears justInstalledUpdate',
      () async {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 1,
        });
        final provisioner = buildProvisioner(manifestVersion: 3, onWifi: true);
        await provisioner.ensureUpToDateInBackground();
        expect(provisioner.justInstalledUpdate, isNotNull);

        provisioner.dismissJustInstalledUpdate();

        expect(provisioner.justInstalledUpdate, isNull);
      },
    );

    test(
      'checkForUpdate rejects a manifest advertising an unsupported schema version',
      () async {
        var downloadRequested = false;
        final provisioner = buildProvisioner(
          schemaVersion: ReferenceDatabaseProvisioner.supportedSchemaVersion + 1,
          onDownloadRequested: () => downloadRequested = true,
        );

        await expectLater(
          provisioner.checkForUpdate(),
          throwsA(isA<DataFormatException>()),
        );

        expect(downloadRequested, isFalse);
        expect(await provisioner.hasUsableLocalCopy(), isFalse);
      },
    );

    test(
      'ensureUpToDateInBackground never throws even if the manifest fetch fails',
      () async {
        final provisioner = ReferenceDatabaseProvisioner(
          client: MockClient((request) async => http.Response('server error', 500)),
          networkAvailability: _FakeNetworkAvailability(),
          foregroundServiceKeeper: const NoopForegroundServiceKeeper(),
        );

        await provisioner.ensureUpToDateInBackground();

        expect(await provisioner.hasUsableLocalCopy(), isFalse);
      },
    );
  });
}
