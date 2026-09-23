import 'package:discere/app/main_screen/main_screen_page.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
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
// answers with one, and the check itself — version comparison, Wi-Fi gating,
// the pending update the UI listens to — runs for real from there, as does
// the production dialog in main_screen_page.dart.

/// Reports a newer version than anything the test installs, without touching
/// the network. Downloading it still fails, which is what the second test
/// below relies on.
class _UpdateAvailableDownloader implements ReferenceDbDownloader {
  @override
  Future<ReferenceDbManifest> fetchManifest() async => const ReferenceDbManifest(
    version: 2,
    schemaVersion: ReferenceDatabaseProvisioner.supportedSchemaVersion,
    url: 'https://example.invalid/reference.db.gz',
    sha256: '',
    compressedSizeBytes: 1024,
  );

  @override
  Future<void> downloadAndInstall(
    ReferenceDbManifest manifest,
    String destinationPath, {
    required void Function(double progress)? onProgress,
  }) async {
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
      'declining it leaves the update pending for the next app start',
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

        final provisioner = Provider.of<ReferenceDatabaseProvisioner>(
          context,
          listen: false,
        );
        expect(find.text(loc.referenceDbUpdateConfirmUpdateNow), findsOneWidget);
        expect(find.text(loc.referenceDbDownloadConfirmNotNow), findsOneWidget);

        await tester.tap(find.text(loc.referenceDbDownloadConfirmNotNow));
        await safePumpAndSettle(tester);

        expect(find.text(loc.referenceDbUpdateConfirmTitle), findsNothing);
        // Declining doesn't persist anything — the provisioner itself
        // re-surfaces a still-newer version on the next real background
        // check (see reference_database_provisioner_test.dart), so it isn't
        // re-verified through the dialog here.
        expect(provisioner.pendingUpdate, isNull);
      },
      timeout: integrationTestTimeout,
    );

    testWidgets(
      'confirming the update dialog attempts to download it',
      (tester) async {
        final mockNotificationService = createMockNotificationService();
        await startApp(
          tester,
          notificationService: mockNotificationService,
          referenceDbDownloader: _UpdateAvailableDownloader(),
        );

        final context = tester.element(find.byType(MainScreenPage));
        final loc = AppLocalizations.of(context)!;

        final provisioner = Provider.of<ReferenceDatabaseProvisioner>(
          context,
          listen: false,
        );
        await provisioner.ensureUpToDateInBackground();
        await safePumpAndSettle(tester);

        await tester.tap(find.text(loc.referenceDbUpdateConfirmUpdateNow));
        await safePumpAndSettle(tester);

        expect(find.text(loc.referenceDbUpdateConfirmTitle), findsNothing);
        // The real download can't succeed here (HTTP is forced to fail fast —
        // see this file's top comment), so confirming surfaces the resulting
        // error instead of silently doing nothing.
        await waitForFinder(tester, find.byType(SnackBar));
      },
      timeout: integrationTestTimeout,
    );
  });
}
