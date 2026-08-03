import 'package:discere/app/about_page.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const packageInfoChannel = MethodChannel(
    'dev.fluttercommunity.plus/package_info',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, (call) async {
          if (call.method == 'getAll') {
            return {
              'appName': 'Discere',
              'packageName': 'com.example.discere',
              'version': '1.0.0',
              'buildNumber': '1',
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, null);
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
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const AboutPage(),
  );
}
