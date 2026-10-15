import 'dart:async';
import 'dart:io';

import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_update_service.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
import 'package:discere/shared/persistence/staged_reference_db.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/reference_db_updates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;
  late FakeReferenceDbDownloader downloader;
  late ReferenceDbUpdateService updates;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reference_db_updates');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => tempDir.path);
    SharedPreferences.setMockInitialValues({
      ReferenceDatabaseProvisioner.prefKeyVersion: 2,
    });
    downloader = FakeReferenceDbDownloader();
    updates = buildReferenceDbUpdates(downloader);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tempDir.delete(recursive: true);
  });

  /// The version of an available update, or null for any other state.
  int? availableVersion() => switch (updates.state) {
    ReferenceDbUpdateAvailable(:final update) => update.version,
    _ => null,
  };

  group('the check at start', () {
    test('has not run before it is started', () {
      expect(updates.state, isA<ReferenceDbUpdateNotChecked>());
    });

    test('is checking while the manifest is fetched, then offers a newer '
        'version through the start dialog', () async {
      final states = <ReferenceDbUpdateState>[];
      updates.addListener(() => states.add(updates.state));

      await updates.checkAtStart();

      expect(states.first, isA<ReferenceDbUpdateChecking>());
      expect(availableVersion(), 3);
      expect(updates.startOffer?.version, 3);
    });

    test('says up to date when nothing is newer', () async {
      downloader.manifestVersion = 2;

      await updates.checkAtStart();

      expect(updates.state, isA<ReferenceDbUpToDate>());
      expect(updates.startOffer, isNull);
    });

    test('ends in a failed check rather than throwing', () async {
      downloader.manifestError = NetworkException('offline');

      await updates.checkAtStart();

      expect(updates.state, isA<ReferenceDbUpdateCheckFailed>());
    });

    test(
      'starts anew after a restart that installed what was staged',
      () async {
        await updates.checkAtStart();
        await updates.download();
        expect(updates.state, isA<ReferenceDbUpdateStaged>());

        downloader.manifestVersion = 2;
        await updates.checkAtStart();

        expect(updates.state, isA<ReferenceDbUpToDate>());
      },
    );
  });

  group('declining', () {
    test('keeps the update, as declined, and takes it out of the start '
        'dialog', () async {
      await updates.checkAtStart();

      updates.decline();

      final state = updates.state;
      expect(state, isA<ReferenceDbUpdateAvailable>());
      expect((state as ReferenceDbUpdateAvailable).declined, isTrue);
      expect(updates.startOffer, isNull);
    });

    test('still lets the update be downloaded by hand', () async {
      await updates.checkAtStart();
      updates.decline();

      await updates.download();

      expect(updates.state, isA<ReferenceDbUpdateStaged>());
      final staged = StagedReferenceDb(
        await ReferenceDatabaseProvisioner.resolveLocalPath(),
      );
      expect((await staged.readMetadata())?.version, 3);
    });
  });

  group('a check by hand', () {
    test('shows a newer version without offering it through the start '
        'dialog', () async {
      downloader.manifestVersion = 2;
      await updates.checkAtStart();
      downloader.manifestVersion = 3;

      await updates.checkNow();

      expect(availableVersion(), 3);
      expect(updates.startOffer, isNull);
    });

    test('also runs when nothing was checked at start', () async {
      await updates.checkNow();
      expect(availableVersion(), 3);
    });

    test('does not run while an update is found or downloading', () async {
      await updates.checkAtStart();
      downloader.manifestError = NetworkException('would fail');

      await updates.checkNow();

      expect(availableVersion(), 3);
    });
  });

  group('the download', () {
    test('runs once, however often it is started', () async {
      await updates.checkAtStart();
      downloader.release = Completer<void>();

      final first = updates.download();
      final second = updates.download();
      expect(updates.state, isA<ReferenceDbUpdateDownloading>());
      downloader.release!.complete();
      await (first, second).wait;

      expect(downloader.downloads, 1);
      expect(updates.state, isA<ReferenceDbUpdateStaged>());
    });

    test('reports its progress once per percentage point', () async {
      await updates.checkAtStart();
      downloader.progressSteps = [
        for (var step = 0; step <= 1000; step++) step / 1000,
      ];
      final reported = <double?>[];
      updates.addListener(() {
        if (updates.state case ReferenceDbUpdateDownloading(:final progress)) {
          reported.add(progress);
        }
      });

      await updates.download();

      // The start without progress, then 0 %, 1 %, ... 100 %.
      expect(reported.first, isNull);
      expect(reported.skip(1).map((p) => (p! * 100).floor()), [
        for (var percent = 0; percent <= 100; percent++) percent,
      ]);
    });

    test('ends in a failure that can be tried again', () async {
      await updates.checkAtStart();
      downloader.downloadError = NetworkException('offline');

      await updates.download();
      expect(updates.state, isA<ReferenceDbUpdateDownloadFailed>());

      downloader.downloadError = null;
      await updates.download();

      expect(updates.state, isA<ReferenceDbUpdateStaged>());
      expect(downloader.downloads, 2);
    });

    test(
      'a failure put aside leaves the update available, as declined',
      () async {
        await updates.checkAtStart();
        downloader.downloadError = NetworkException('offline');
        await updates.download();

        updates.dismissDownloadFailure();

        final state = updates.state as ReferenceDbUpdateAvailable;
        expect(state.declined, isTrue);
        expect(updates.startOffer, isNull);
      },
    );

    test('once staged, its notice can be put aside', () async {
      await updates.checkAtStart();
      await updates.download();

      updates.dismissStagedNotice();

      final state = updates.state as ReferenceDbUpdateStaged;
      expect(state.version, 3);
      expect(state.noticeDismissed, isTrue);
    });
  });
}
