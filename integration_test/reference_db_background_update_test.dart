import 'package:discere/app/main_screen/main_screen_page.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
import 'package:discere/shared/persistence/reference_db_manifest.dart';
import 'package:discere/shared/persistence/reference_db_update_service.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'test_utils.dart';

// Covers https://github.com/discere-app/discere/issues/140: a reference-DB
// update must never install without the user's explicit consent — on
// Wi-Fi or cellular alike — so the main screen shows a confirmation dialog
// (matching the first-launch download-confirm screen) instead of installing
// silently or only warning about cellular data use.
//
// All HTTP is forced to fail fast in integration tests (see test_utils.dart's
// _FastFailHttpOverrides), so a real manifest fetch can never report a newer
// version here. The app is therefore started with a stand-in downloader that
// answers with one, and the check itself — version comparison, the update
// state the UI listens to — runs for real from there, as do the production
// dialog, the notice below every route and the settings entry.

/// Reports a newer version than anything the test installs, without touching
/// the network. Downloading it still fails, which is what the tests of the
/// download below rely on.
class _UpdateAvailableDownloader implements ReferenceDbDownloader {
  int downloads = 0;

  @override
  Future<ReferenceDbManifest> fetchManifest() async =>
      const ReferenceDbManifest([
        ReferenceDbRelease(
          version: 2,
          schemaVersion: 2,
          url: 'https://example.invalid/reference.db.gz',
          sha256: '',
          compressedSizeBytes: 1024,
        ),
      ]);

  @override
  Future<void> downloadAndInstall(
    ReferenceDbRelease release,
    String destinationPath, {
    required void Function(double progress)? onProgress,
  }) async {
    downloads++;
    throw NetworkException('No connection in this test.');
  }
}

void main() {
  initializeIntegrationTest();

  group('reference db background update', () {
    setUp(() async {
      await resetTestState();
    });

    testWidgets(
      'a pending reference-DB update shows a confirmation dialog, and '
      'declining it keeps the update known for this session',
      (tester) async {
        final mockNotificationService = createMockNotificationService();
        await startApp(
          tester,
          notificationService: mockNotificationService,
          referenceDbDownloader: _UpdateAvailableDownloader(),
        );

        final context = tester.element(find.byType(MainScreenPage));
        final loc = AppLocalizations.of(context)!;

        // The bootstrap runs the background check itself, so the dialog
        // arrives on its own once the stand-in downloader reports a newer
        // version — no frame is scheduled by that check, hence the wait.
        await waitForFinder(
          tester,
          find.text(loc.referenceDbUpdateConfirmTitle),
          description: 'the reference-DB update dialog',
        );

        final updates = Provider.of<ReferenceDbUpdateService>(
          context,
          listen: false,
        );
        expect(
          find.text(loc.referenceDbUpdateConfirmUpdateNow),
          findsOneWidget,
        );
        expect(find.text(loc.referenceDbDownloadConfirmNotNow), findsOneWidget);

        await tester.tap(find.text(loc.referenceDbDownloadConfirmNotNow));
        await safePumpAndSettle(tester);

        expect(find.text(loc.referenceDbUpdateConfirmTitle), findsNothing);
        // Declining doesn't persist anything; the next start's check offers
        // a still-newer version again (see reference_db_update_service_test).
        final state = updates.state;
        expect(state, isA<ReferenceDbUpdateAvailable>());
        expect((state as ReferenceDbUpdateAvailable).declined, isTrue);
        expect(updates.startOffer, isNull);
      },
      timeout: integrationTestTimeout,
    );

    testWidgets(
      'confirming the update dialog downloads it in the background, and a '
      'failed download offers to try again in the notice',
      (tester) async {
        final mockNotificationService = createMockNotificationService();
        await startApp(
          tester,
          notificationService: mockNotificationService,
          referenceDbDownloader: _UpdateAvailableDownloader(),
        );

        final context = tester.element(find.byType(MainScreenPage));
        final loc = AppLocalizations.of(context)!;
        await waitForFinder(
          tester,
          find.text(loc.referenceDbUpdateConfirmTitle),
          description: 'the reference-DB update dialog',
        );

        await tester.tap(find.text(loc.referenceDbUpdateConfirmUpdateNow));
        await safePumpAndSettle(tester);

        expect(find.text(loc.referenceDbUpdateConfirmTitle), findsNothing);
        // It can't succeed here (HTTP is forced to fail fast — see this
        // file's top comment), so the notice reports the failure, in words,
        // instead of silently doing nothing.
        await waitForFinder(
          tester,
          find.byKey(const Key('reference_db_download_failed_notice')),
          description: 'the notice of the failed download',
        );
        expect(find.textContaining(loc.errorNetwork), findsOneWidget);
        expect(
          find.byKey(const Key('reference_db_download_retry_button')),
          findsOneWidget,
        );
      },
      timeout: integrationTestTimeout,
    );

    testWidgets(
      'an update declined at start can still be downloaded from the settings',
      (tester) async {
        final downloader = _UpdateAvailableDownloader();
        await startApp(
          tester,
          notificationService: createMockNotificationService(),
          referenceDbDownloader: downloader,
        );
        final loc = AppLocalizations.of(
          tester.element(find.byType(MainScreenPage)),
        )!;
        await waitForFinder(
          tester,
          find.text(loc.referenceDbUpdateConfirmTitle),
          description: 'the reference-DB update dialog',
        );
        await tester.tap(find.text(loc.referenceDbDownloadConfirmNotNow));
        await safePumpAndSettle(tester);

        await tester.tap(find.byIcon(Icons.settings).last);
        await safePumpAndSettle(tester);
        final download = find.byKey(
          const Key('settings_reference_db_download_button'),
        );
        await tester.scrollUntilVisible(
          download,
          200.0,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(download);
        await waitForFinder(
          tester,
          find.text(loc.referenceDbUpdateConfirmTitle),
          description: 'the same confirmation as at start',
        );
        await tester.tap(find.text(loc.referenceDbUpdateConfirmUpdateNow));

        await waitForFinder(
          tester,
          find.byKey(const Key('reference_db_download_failed_notice')),
          description: 'the notice of the download started from the settings',
        );
        expect(downloader.downloads, 1);
      },
      timeout: integrationTestTimeout,
    );
  });
}
