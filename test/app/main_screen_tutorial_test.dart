import 'package:discere/app/main_screen_tutorial.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the includePreviouslySeenSteps split: a user who
/// already dismissed the original two-step tour (deckFav/watchlist) must
/// still see the deckEdit step added later, on its own — not have it
/// silently suppressed by the tour's original "seen" flag, and not have the
/// already-seen steps replayed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTutorial(
    WidgetTester tester, {
    required bool includePreviouslySeenSteps,
  }) async {
    final deckFavKey = GlobalKey();
    final deckEditKey = GlobalKey();
    final watchlistKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                Icon(Icons.favorite, key: deckFavKey),
                Icon(Icons.edit, key: deckEditKey),
                Icon(Icons.star, key: watchlistKey),
                TextButton(
                  onPressed: () => MainScreenTutorial(
                    deckFavKey: deckFavKey,
                    deckEditKey: deckEditKey,
                    watchlistKey: watchlistKey,
                    includePreviouslySeenSteps: includePreviouslySeenSteps,
                  ).show(context),
                  child: const Text('show'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    // TutorialCoachMark's overlay never settles once shown (see
    // deck_page_multiple_choice_test.dart's tutorial test), so
    // pumpAndSettle() can't be used here.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  // TutorialCoachMark shows one target at a time, advancing only on a tap
  // on its own overlay (no test precedent for driving that — see
  // deck_page_multiple_choice_test.dart's tutorial test) — so these assert
  // on the first step shown, which is exactly what distinguishes the two
  // modes: the full tour announces itself first, the solo deckEdit step
  // jumps straight to the point instead of re-announcing a "tour".
  testWidgets('announces the tour first for a first-time user', (tester) async {
    await pumpTutorial(tester, includePreviouslySeenSteps: true);

    expect(find.text('Quick tour'), findsOneWidget);
    expect(find.text('Edit deck'), findsNothing);
  });

  testWidgets(
    'jumps straight to the deckEdit step for a user who already saw the '
    'original tour, without re-announcing it',
    (tester) async {
      await pumpTutorial(tester, includePreviouslySeenSteps: false);

      expect(find.text('Quick tour'), findsNothing);
      expect(find.text('Edit deck'), findsOneWidget);
    },
  );
}
