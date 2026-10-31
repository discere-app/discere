import 'package:discere/external/wikipedia/wikipedia_api.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  group('about page', () {
    setUp(() async {
      await resetTestState();
    });

    testWidgets(
      'About page shows a licenses section that opens the license page',
      (tester) async {
        final mockNotificationService = createMockNotificationService();
        await startApp(tester, notificationService: mockNotificationService);

        // Navigate to Settings
        await tester.tap(find.byIcon(Icons.settings).last);
        await safePumpAndSettle(tester);

        // Tap on About
        final aboutTile = find.byKey(const Key('settings_about_tile'));
        expect(aboutTile, findsOneWidget);
        await tester.tap(aboutTile);
        await safePumpAndSettle(tester);

        // Scroll to the Licenses section and open it
        final scrollable = find.byType(Scrollable).last;
        final licensesButton = find.widgetWithText(
          OutlinedButton,
          'Show licenses',
        );
        await tester.scrollUntilVisible(
          licensesButton,
          200.0,
          scrollable: scrollable,
        );
        expect(licensesButton, findsOneWidget);

        await tester.tap(licensesButton);
        await safePumpAndSettle(tester);

        // Verify the built-in license page opened
        expect(find.byType(LicensePage), findsOneWidget);

        // Go back to the About page
        await tester.tap(find.byType(BackButton));
        await safePumpAndSettle(tester);

        expect(find.text('About Discere'), findsOneWidget);
      },
      timeout: integrationTestTimeout,
    );

    // The one place the version the build carries — pubspec.yaml's, with
    // the `-dev` suffix of an Android debug build — can be compared with
    // what the app reports: a host test has no platform to read it from.
    testWidgets(
      "About page and every request report the installed app's version",
      (tester) async {
        final installed = await PackageInfo.fromPlatform();
        final sent = <http.BaseRequest>[];
        await startApp(
          tester,
          notificationService: createMockNotificationService(),
          httpClient: MockClient((request) async {
            sent.add(request);
            // 404 rather than a 5xx, which would put the host into a cooldown.
            return http.Response('{}', 404);
          }),
        );

        await Provider.of<WikipediaApi>(
          tester.element(find.byType(MaterialApp)),
          listen: false,
        ).getSummary(
          wikipediaUrl: 'https://en.wikipedia.org/wiki/Pterois_miles',
          localeCode: 'en',
        );

        expect(
          sent.map((request) => request.url.host),
          contains('en.wikipedia.org'),
        );
        expect(
          sent.map((request) => request.headers['User-Agent']),
          everyElement(AppConstants.userAgentFor(installed.version)),
        );

        await tester.tap(find.byIcon(Icons.settings).last);
        await safePumpAndSettle(tester);
        await tester.tap(find.byKey(const Key('settings_about_tile')));
        await safePumpAndSettle(tester);

        expect(find.text('Version ${installed.version}'), findsOneWidget);
      },
      timeout: integrationTestTimeout,
    );
  });
}
