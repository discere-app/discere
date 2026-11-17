import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/l10n/app_localizations_delegates.dart';
import 'package:discere/shared/ui/coach_mark_tour.dart';
import 'package:discere/theme/ocean_theme/ocean_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

/// A tour keeps the app's typography although tutorial_coach_mark lays a
/// default text style from the SDK's theme — which the app never sets — over
/// its overlay.
void main() {
  final appFontFamily = oceanTheme.textTheme.bodyMedium!.fontFamily;

  TextStyle renderedStyle(WidgetTester tester, String text) => tester
      .widget<RichText>(
        find.descendant(of: find.text(text), matching: find.byType(RichText)),
      )
      .text
      .style!;

  Widget app(Widget home) => MaterialApp(
    locale: const Locale('en'),
    theme: oceanTheme,
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  setUpAll(() {
    expect(appFontFamily, isNotNull);
  });

  testWidgets('step content takes its font from the app theme, not from the '
      'inherited text style', (tester) async {
    await tester.pumpWidget(
      app(
        const DefaultTextStyle(
          style: TextStyle(fontFamily: 'Roboto'),
          child: CoachMarkContent(title: 'Title', body: 'Body'),
        ),
      ),
    );

    expect(renderedStyle(tester, 'Title').fontFamily, appFontFamily);
    expect(renderedStyle(tester, 'Body').fontFamily, appFontFamily);
  });

  testWidgets('a shown tour renders its step and skip button in the app '
      'font', (tester) async {
    final targetKey = GlobalKey();
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                Icon(Icons.star, key: targetKey),
                TextButton(
                  onPressed: () => showCoachMarkTour(
                    context,
                    targets: [
                      TargetFocus(
                        identify: 'star',
                        keyTarget: targetKey,
                        contents: [
                          TargetContent(
                            child: const CoachMarkContent(
                              title: 'Title',
                              body: 'Body',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  child: const Text('show'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    // The overlay's pulse animation never settles (see
    // main_screen_tutorial_test.dart).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(renderedStyle(tester, 'Title').fontFamily, appFontFamily);
    expect(renderedStyle(tester, 'Skip').fontFamily, appFontFamily);
  });
}
