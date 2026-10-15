import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
import 'package:discere/shared/persistence/reference_db_update_check.dart';
import 'package:discere/shared/persistence/staged_reference_db.dart';
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
  var closeCalls = 0;
  late List<int> compressedBytes;
  late String checksum;

  http.Client buildMockClient({
    int manifestVersion = 3,
    int schemaVersion = 2,
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
    int schemaVersion = 2,
    String? checksumOverride,
    void Function()? onDownloadRequested,
    bool onWifi = true,
  }) {
    return ReferenceDatabaseProvisioner(
      downloader: ReferenceDbDownloader(
        client: buildMockClient(
          manifestVersion: manifestVersion,
          schemaVersion: schemaVersion,
          checksumOverride: checksumOverride,
          onDownloadRequested: onDownloadRequested,
        ),
        foregroundServiceKeeper: const NoopForegroundServiceKeeper(),
      ),
      networkAvailability: _FakeNetworkAvailability(onWifi: onWifi),
      closeOpenDatabases: () async => closeCalls++,
    );
  }

  setUp(() async {
    closeCalls = 0;
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
    test('currentVersion returns null when none has ever been installed', () async {
      expect(await ReferenceDatabaseProvisioner.currentVersion(), isNull);
    });

    test('currentVersion returns the stamped version', () async {
      SharedPreferences.setMockInitialValues({
        ReferenceDatabaseProvisioner.prefKeyVersion: 5,
      });
      expect(await ReferenceDatabaseProvisioner.currentVersion(), 5);
    });

    test('hasUsableLocalCopy reflects file presence', () async {
      SharedPreferences.setMockInitialValues({
        ReferenceDatabaseProvisioner.prefKeySchemaVersion:
            2,
      });
      final provisioner = buildProvisioner();
      expect(await provisioner.hasUsableLocalCopy(), isFalse);

      final path = await ReferenceDatabaseProvisioner.resolveLocalPath();
      await File(path).create(recursive: true);

      expect(await provisioner.hasUsableLocalCopy(), isTrue);
    });

    test('this app build supports schema 1 and 2 — the second the first '
        'with entity aliases', () {
      // Pinned as a literal: a test written against the constant would pass
      // whatever it is set to.
      expect(ReferenceDatabaseProvisioner.supportedSchemaVersions, {1, 2});
    });

    test('an installed schema-1 copy stays usable', () async {
      SharedPreferences.setMockInitialValues({
        ReferenceDatabaseProvisioner.prefKeySchemaVersion: 1,
      });
      final path = await ReferenceDatabaseProvisioner.resolveLocalPath();
      await File(path).create(recursive: true);

      expect(await buildProvisioner().hasUsableLocalCopy(), isTrue);
    });

    test('hasUsableLocalCopy treats a pre-existing file with no stored schema '
        'version as a schema-1 file: stamps it, and keeps it usable',
        () async {
      final provisioner = buildProvisioner();
      final path = await ReferenceDatabaseProvisioner.resolveLocalPath();
      await File(path).create(recursive: true);

      expect(await provisioner.hasUsableLocalCopy(), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(ReferenceDatabaseProvisioner.prefKeySchemaVersion),
        1,
      );
    });

    test('hasUsableLocalCopy rejects a file installed under a schema this '
        'build does not support, even though the file itself exists', () async {
      final provisioner = buildProvisioner();
      final path = await ReferenceDatabaseProvisioner.resolveLocalPath();
      await File(path).create(recursive: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        ReferenceDatabaseProvisioner.prefKeySchemaVersion,
        3,
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
          2,
        );
      },
    );

    test('downloadAndInstall removes the journal files of the database it '
        'replaces', () async {
      final path = await ReferenceDatabaseProvisioner.resolveLocalPath();
      await File(path).create(recursive: true);
      for (final suffix in const ['-wal', '-shm', '-journal']) {
        await File('$path$suffix').writeAsString('old');
      }
      final provisioner = buildProvisioner();

      await provisioner.downloadAndInstall(
        await provisioner.checkForUpdate(),
        onProgress: null,
      );

      expect(await File(path).readAsBytes(), rawDbBytes);
      for (final suffix in const ['-wal', '-shm', '-journal']) {
        expect(await File('$path$suffix').exists(), isFalse, reason: suffix);
      }
    });

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
      'ensureUpToDateInBackground clears pendingUpdate when already up to date',
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
        expect(provisioner.pendingUpdate, isNull);
      },
    );

    test(
      'ensureUpToDateInBackground surfaces pendingUpdate on Wi-Fi without '
      'downloading automatically',
      () async {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 1,
        });
        var downloadRequested = false;
        final provisioner = buildProvisioner(
          manifestVersion: 3,
          onWifi: true,
          onDownloadRequested: () => downloadRequested = true,
        );

        await provisioner.ensureUpToDateInBackground();

        expect(downloadRequested, isFalse);
        expect(await provisioner.hasUsableLocalCopy(), isFalse);
        expect(provisioner.pendingUpdate?.version, 3);
        expect(provisioner.pendingUpdateOnWifi, isTrue);
      },
    );

    test(
      'ensureUpToDateInBackground surfaces pendingUpdate off Wi-Fi without '
      'downloading',
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
        expect(provisioner.pendingUpdate?.version, 3);
        expect(provisioner.pendingUpdateOnWifi, isFalse);
      },
    );

    group('an update found during a session', () {
      late String activePath;

      setUp(() async {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 1,
          ReferenceDatabaseProvisioner.prefKeySchemaVersion: 2,
        });
        activePath = await ReferenceDatabaseProvisioner.resolveLocalPath();
        await File(activePath).writeAsString('active database');
      });

      Future<ReferenceDatabaseProvisioner> staged() async {
        final provisioner = buildProvisioner(manifestVersion: 3);
        await provisioner.ensureUpToDateInBackground();
        await provisioner.downloadPendingUpdate();
        return provisioner;
      }

      test('is staged next to the active file, neither installed nor '
          'stamped', () async {
        final provisioner = await staged();

        expect(await File(activePath).readAsString(), 'active database');
        expect(
          await File(StagedReferenceDb(activePath).filePath).readAsBytes(),
          rawDbBytes,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(ReferenceDatabaseProvisioner.prefKeyVersion), 1);
        expect(provisioner.pendingUpdate, isNull);
        expect(provisioner.hasStagedUpdateToApply, isTrue);
        expect(provisioner.takeInstalledThisStart(), isFalse);
      });

      test('can have its notice put aside and stays staged', () async {
        final provisioner = await staged();

        provisioner.dismissStagedUpdateNotice();

        expect(provisioner.hasStagedUpdateToApply, isFalse);
        expect(await StagedReferenceDb(activePath).hasFile, isTrue);
      });

      test('is installed and stamped by installStagedUpdate', () async {
        await staged();
        final provisioner = buildProvisioner(manifestVersion: 3);

        await provisioner.installStagedUpdate();

        expect(await File(activePath).readAsBytes(), rawDbBytes);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(ReferenceDatabaseProvisioner.prefKeyVersion), 3);
        expect(await StagedReferenceDb(activePath).hasFile, isFalse);
        expect(await StagedReferenceDb(activePath).readMetadata(), isNull);
        expect(provisioner.takeInstalledThisStart(), isTrue);
      });
    });

    group('installStagedUpdate', () {
      late String activePath;
      late StagedReferenceDb staging;

      setUp(() async {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 1,
          ReferenceDatabaseProvisioner.prefKeySchemaVersion: 2,
        });
        activePath = await ReferenceDatabaseProvisioner.resolveLocalPath();
        await File(activePath).writeAsString('active database');
        staging = StagedReferenceDb(activePath);
      });

      Future<void> stage({
        int version = 3,
        int schemaVersion = 2,
        bool withFile = true,
        bool withMetadata = true,
      }) async {
        if (withFile) await File(staging.filePath).writeAsString('staged');
        if (withMetadata) {
          await staging.writeMetadata(
            version: version,
            schemaVersion: schemaVersion,
          );
        }
      }

      Future<int?> installedVersion() async => (await SharedPreferences
          .getInstance()).getInt(ReferenceDatabaseProvisioner.prefKeyVersion);

      Future<void> expectDiscarded() async {
        expect(await File(activePath).readAsString(), 'active database');
        expect(await installedVersion(), 1);
        expect(await staging.hasFile, isFalse);
        expect(await staging.readMetadata(), isNull);
      }

      test('discards a staging whose schema this build does not support',
          () async {
        await stage(schemaVersion: 3);
        await buildProvisioner().installStagedUpdate();
        await expectDiscarded();
      });

      test('discards a staging no newer than what is installed', () async {
        await stage(version: 1);
        await buildProvisioner().installStagedUpdate();
        await expectDiscarded();
      });

      test('discards a staging that never got its metadata', () async {
        await stage(withMetadata: false);
        await buildProvisioner().installStagedUpdate();
        await expectDiscarded();
      });

      test('after a start that moved the file into place and stopped before '
          'stamping it, stamps it', () async {
        // The active file is the staged one already; only metadata is left.
        await stage(withFile: false);
        final provisioner = buildProvisioner();

        await provisioner.installStagedUpdate();

        expect(await File(activePath).readAsString(), 'active database');
        expect(await installedVersion(), 3);
        expect(await staging.readMetadata(), isNull);
        expect(provisioner.takeInstalledThisStart(), isTrue);
      });

      test('after a start that stamped and stopped before clearing up, only '
          'clears up', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(ReferenceDatabaseProvisioner.prefKeyVersion, 3);
        await stage(withFile: false);

        await buildProvisioner().installStagedUpdate();

        expect(await installedVersion(), 3);
        expect(await staging.readMetadata(), isNull);
      });

      Future<void> leaveJournalFiles() async {
        for (final suffix in const ['-wal', '-shm', '-journal']) {
          await File('$activePath$suffix').writeAsString('old $suffix');
        }
      }

      Future<List<String>> journalFilesLeft() async => [
        for (final suffix in const ['-wal', '-shm', '-journal'])
          if (await File('$activePath$suffix').exists()) suffix,
      ];

      test('closes the open databases once it has replaced the file, and '
          'not when it only finishes an earlier installation', () async {
        await stage();
        await buildProvisioner().installStagedUpdate();
        expect(closeCalls, 1);

        await stage(version: 4, withFile: false);
        await buildProvisioner().installStagedUpdate();
        expect(closeCalls, 1);
      });

      test('removes the journal files the replaced database left', () async {
        await leaveJournalFiles();
        await stage();

        await buildProvisioner().installStagedUpdate();

        expect(await File(activePath).readAsString(), 'staged');
        expect(await journalFilesLeft(), isEmpty);
      });

      test('removes them as well when resuming after the rename', () async {
        await leaveJournalFiles();
        await stage(withFile: false);

        await buildProvisioner().installStagedUpdate();

        expect(await journalFilesLeft(), isEmpty);
      });

      test('leaves everything alone when nothing is staged', () async {
        await leaveJournalFiles();
        final provisioner = buildProvisioner();
        await provisioner.installStagedUpdate();

        expect(await File(activePath).readAsString(), 'active database');
        expect(await installedVersion(), 1);
        expect(provisioner.takeInstalledThisStart(), isFalse);
        expect(await journalFilesLeft(), ['-wal', '-shm', '-journal']);
      });
    });

    group('updateCheck', () {
      setUp(() {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 1,
        });
      });

      test('is running until the background check ends', () {
        expect(
          buildProvisioner().updateCheck,
          isA<ReferenceDbUpdateCheckRunning>(),
        );
      });

      test('keeps a newer version the user declined, as declined', () async {
        final provisioner = buildProvisioner(manifestVersion: 3);
        await provisioner.ensureUpToDateInBackground();

        provisioner.dismissPendingUpdate();

        expect(provisioner.pendingUpdate, isNull);
        final check = provisioner.updateCheck;
        expect(check, isA<ReferenceDbNewerVersionFound>());
        check as ReferenceDbNewerVersionFound;
        expect(check.version, 3);
        expect(check.declined, isTrue);
      });

      test('offers a declined version anew on the next check', () async {
        final provisioner = buildProvisioner(manifestVersion: 3);
        await provisioner.ensureUpToDateInBackground();
        provisioner.dismissPendingUpdate();

        await provisioner.ensureUpToDateInBackground();

        final check = provisioner.updateCheck as ReferenceDbNewerVersionFound;
        expect(check.declined, isFalse);
      });

      test('says up to date, and tells the listeners, when nothing is '
          'newer', () async {
        final provisioner = buildProvisioner(manifestVersion: 1);
        var notified = 0;
        provisioner.addListener(() => notified++);

        await provisioner.ensureUpToDateInBackground();

        expect(provisioner.updateCheck, isA<ReferenceDbUpToDate>());
        expect(notified, greaterThan(0));
      });

      test('says failed when the manifest cannot be used', () async {
        final provisioner = buildProvisioner(
          manifestVersion: 3,
          schemaVersion: 9,
        );

        await provisioner.ensureUpToDateInBackground();

        expect(provisioner.updateCheck, isA<ReferenceDbUpdateCheckFailed>());
        expect(provisioner.pendingUpdate, isNull);
      });

      test('says up to date after the blocking download installed the '
          'newest version', () async {
        SharedPreferences.setMockInitialValues({});
        final provisioner = buildProvisioner(manifestVersion: 3);

        await provisioner.downloadAndInstall(
          await provisioner.checkForUpdate(),
          onProgress: null,
        );

        expect(provisioner.updateCheck, isA<ReferenceDbUpToDate>());
      });
    });

    test('dismissPendingUpdate clears the pending update without '
        'downloading', () async {
      SharedPreferences.setMockInitialValues({
        ReferenceDatabaseProvisioner.prefKeyVersion: 1,
      });
      var downloadRequested = false;
      final provisioner = buildProvisioner(
        manifestVersion: 3,
        onWifi: true,
        onDownloadRequested: () => downloadRequested = true,
      );
      await provisioner.ensureUpToDateInBackground();
      expect(provisioner.pendingUpdate, isNotNull);

      provisioner.dismissPendingUpdate();

      expect(provisioner.pendingUpdate, isNull);
      expect(downloadRequested, isFalse);
    });

    test(
      'a dismissed update is re-surfaced by the next '
      'ensureUpToDateInBackground call (i.e. the next app start)',
      () async {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 1,
        });
        final provisioner = buildProvisioner(manifestVersion: 3, onWifi: true);
        await provisioner.ensureUpToDateInBackground();
        provisioner.dismissPendingUpdate();
        expect(provisioner.pendingUpdate, isNull);

        await provisioner.ensureUpToDateInBackground();

        expect(provisioner.pendingUpdate?.version, 3);
      },
    );

    test('checkForUpdate accepts schema-1 and schema-2 manifests and rejects '
        'a schema-3 one', () async {
      for (final schemaVersion in const [1, 2]) {
        final accepted = await buildProvisioner(
          schemaVersion: schemaVersion,
        ).checkForUpdate();
        expect(accepted.version, 3, reason: 'schema $schemaVersion');
      }

      await expectLater(
        buildProvisioner(schemaVersion: 3).checkForUpdate(),
        throwsA(isA<DataFormatException>()),
      );
    });

    test(
      'checkForUpdate rejects a manifest advertising an unsupported schema version',
      () async {
        var downloadRequested = false;
        final provisioner = buildProvisioner(
          schemaVersion: 3,
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
          downloader: ReferenceDbDownloader(
            client: MockClient(
              (request) async => http.Response('server error', 500),
            ),
            foregroundServiceKeeper: const NoopForegroundServiceKeeper(),
          ),
          networkAvailability: _FakeNetworkAvailability(),
          closeOpenDatabases: () async {},
        );

        await provisioner.ensureUpToDateInBackground();

        expect(await provisioner.hasUsableLocalCopy(), isFalse);
      },
    );
  });
}
