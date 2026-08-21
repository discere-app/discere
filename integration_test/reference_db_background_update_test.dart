import 'package:discere/app/main_screen_page.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'test_utils.dart';

// Covers https://github.com/discere-app/discere/issues/140: a reference-DB
// update installed silently in the background on Wi-Fi must still inform the
// user, not just replace a ~90MB file with zero feedback.
//
// The real ensureUpToDateInBackground() network path can't be driven here —
// all HTTP is forced to fail fast in integration tests (see
// test_utils.dart's _FastFailHttpOverrides) so background downloads never
// block the test loop. Instead this drives the exact state transition a
// successful silent install produces via
// ReferenceDatabaseProvisioner.debugMarkBackgroundUpdateInstalled (a
// @visibleForTesting seam), then exercises the real production banner UI in
// main_screen_page.dart from that point on.
void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets(
    'a silent background reference-DB install on Wi-Fi shows a dismissible '
    'banner informing the user',
    (tester) async {
      final mockNotificationService = createMockNotificationService();
      await startApp(tester, notificationService: mockNotificationService);

      final context = tester.element(find.byType(MainScreenPage));
      final loc = AppLocalizations.of(context)!;

      expect(
        find.text(loc.referenceDbJustInstalledBannerMessage),
        findsNothing,
      );

      final provisioner = Provider.of<ReferenceDatabaseProvisioner>(
        context,
        listen: false,
      );
      provisioner.debugMarkBackgroundUpdateInstalled(2);
      await safePumpAndSettle(tester);

      expect(
        find.text(loc.referenceDbJustInstalledBannerMessage),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip(loc.commonClose));
      await safePumpAndSettle(tester);

      expect(
        find.text(loc.referenceDbJustInstalledBannerMessage),
        findsNothing,
      );
      expect(provisioner.justInstalledUpdate, isNull);
    },
    timeout: integrationTestTimeout,
  );
}
