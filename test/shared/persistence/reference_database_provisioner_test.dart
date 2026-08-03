import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      final provisioner = ReferenceDatabaseProvisioner(
        client: buildMockClient(),
      );
      expect(await provisioner.hasUsableLocalCopy(), isFalse);

      final path = await ReferenceDatabaseProvisioner.resolveLocalPath();
      await File(path).create(recursive: true);

      expect(await provisioner.hasUsableLocalCopy(), isTrue);
    });

    test('hasUsableLocalCopy treats a pre-existing file with no stored schema '
        'version as compatible and stamps it for future checks', () async {
      final provisioner = ReferenceDatabaseProvisioner(
        client: buildMockClient(),
      );
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
      final provisioner = ReferenceDatabaseProvisioner(
        client: buildMockClient(),
      );
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
      'downloadInitialCopy downloads, verifies checksum, decompresses and installs',
      () async {
        final provisioner = ReferenceDatabaseProvisioner(
          client: buildMockClient(),
        );
        final progressValues = <double>[];

        await provisioner.downloadInitialCopy(onProgress: progressValues.add);

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
      'downloadInitialCopy rethrows and does not install on checksum mismatch',
      () async {
        final provisioner = ReferenceDatabaseProvisioner(
          client: buildMockClient(checksumOverride: 'deadbeef'),
        );

        await expectLater(
          provisioner.downloadInitialCopy(onProgress: (_) {}),
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
        final provisioner = ReferenceDatabaseProvisioner(
          client: buildMockClient(
            onDownloadRequested: () => downloadRequested = true,
          ),
        );

        await provisioner.ensureUpToDateInBackground();

        expect(downloadRequested, isFalse);
        expect(await provisioner.hasUsableLocalCopy(), isFalse);
      },
    );

    test(
      'ensureUpToDateInBackground downloads when a newer version is available',
      () async {
        SharedPreferences.setMockInitialValues({
          ReferenceDatabaseProvisioner.prefKeyVersion: 1,
        });
        final provisioner = ReferenceDatabaseProvisioner(
          client: buildMockClient(manifestVersion: 3),
        );

        await provisioner.ensureUpToDateInBackground();

        expect(await provisioner.hasUsableLocalCopy(), isTrue);
      },
    );

    test(
      'downloadInitialCopy rejects a manifest advertising an unsupported schema version',
      () async {
        var downloadRequested = false;
        final provisioner = ReferenceDatabaseProvisioner(
          client: buildMockClient(
            schemaVersion:
                ReferenceDatabaseProvisioner.supportedSchemaVersion + 1,
            onDownloadRequested: () => downloadRequested = true,
          ),
        );

        await expectLater(
          provisioner.downloadInitialCopy(onProgress: (_) {}),
          throwsA(isA<DataFormatException>()),
        );

        expect(downloadRequested, isFalse);
        expect(await provisioner.hasUsableLocalCopy(), isFalse);
      },
    );

    test(
      'ensureUpToDateInBackground never throws even if the manifest fetch fails',
      () async {
        final client = MockClient(
          (request) async => http.Response('server error', 500),
        );
        final provisioner = ReferenceDatabaseProvisioner(client: client);

        await provisioner.ensureUpToDateInBackground();

        expect(await provisioner.hasUsableLocalCopy(), isFalse);
      },
    );
  });
}
