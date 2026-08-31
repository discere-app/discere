import 'package:discere/app/main_screen_page.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
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
// The real ensureUpToDateInBackground() network path can't be driven here —
// all HTTP is forced to fail fast in integration tests (see
// test_utils.dart's _FastFailHttpOverrides) so background checks never block
// the test loop. Instead this drives the exact state a real manifest check
// would produce via ReferenceDatabaseProvisioner.debugSetPendingUpdateForTest
// (a @visibleForTesting seam), then exercises the real production dialog UI
// in main_screen_page.dart from that point on.
void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets(
    'a pending reference-DB update shows a confirmation dialog, and '
    'declining it leaves the update pending for the next app start',
    (tester) async {
      final mockNotificationService = createMockNotificationService();
      await startApp(tester, notificationService: mockNotificationService);

      final context = tester.element(find.byType(MainScreenPage));
      final loc = AppLocalizations.of(context)!;

      expect(find.text(loc.referenceDbUpdateConfirmTitle), findsNothing);

      final provisioner = Provider.of<ReferenceDatabaseProvisioner>(
        context,
        listen: false,
      );
      provisioner.debugSetPendingUpdateForTest(2, onWifi: true);
      await safePumpAndSettle(tester);

      expect(find.text(loc.referenceDbUpdateConfirmTitle), findsOneWidget);
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
      await startApp(tester, notificationService: mockNotificationService);

      final context = tester.element(find.byType(MainScreenPage));
      final loc = AppLocalizations.of(context)!;

      final provisioner = Provider.of<ReferenceDatabaseProvisioner>(
        context,
        listen: false,
      );
      provisioner.debugSetPendingUpdateForTest(2, onWifi: true);
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
}
