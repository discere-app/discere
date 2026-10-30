import 'package:discere/app/info/about_page.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('About page shows the version of the installed app', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());

    expect(find.text('Version 2.3.4'), findsOneWidget);
  });

  testWidgets('Tapping the version five times unlocks the developer '
      'diagnostics', (tester) async {
    await tester.pumpWidget(_buildApp());

    for (var tap = 0; tap < 5; tap++) {
      await tester.tap(find.text('Version 2.3.4'));
    }
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(AppConstants.developerDiagnosticsUnlockedPrefKey),
      isTrue,
    );
    expect(find.text('Developer tools unlocked.'), findsOneWidget);
  });

  testWidgets('About page shows a licenses section with a button', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());
    await _scrollToLicensesButton(tester);

    expect(find.text('Licenses'), findsOneWidget);
    expect(
      find.text(
        'Discere uses open-source packages. You can view their licenses here.',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Show licenses'),
      findsOneWidget,
    );
  });

  testWidgets('Tapping the licenses button opens the license page', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());
    await _scrollToLicensesButton(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Show licenses'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });
}

Future<void> _scrollToLicensesButton(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.widgetWithText(OutlinedButton, 'Show licenses'),
    200.0,
    scrollable: find.byType(Scrollable).first,
  );
}

Widget _buildApp() {
  return Provider<PackageInfo>.value(
    value: PackageInfo(
      appName: 'Discere',
      packageName: 'ch.feberle.discere',
      version: '2.3.4',
      buildNumber: '56',
    ),
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AboutPage(),
    ),
  );
}
