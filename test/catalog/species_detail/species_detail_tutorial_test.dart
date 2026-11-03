import 'package:discere/catalog/species_detail/species_detail_tutorial.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// A user who has already seen the "add to deck" coach mark still gets the
/// comparison one, on its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTutorial(
    WidgetTester tester, {
    required bool includeAddToDeck,
  }) async {
    final addToDeckKey = GlobalKey();
    final compareKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
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
                Icon(Icons.playlist_add, key: addToDeckKey),
                Icon(Icons.compare, key: compareKey),
                TextButton(
                  onPressed: () => SpeciesDetailTutorial(
                    addToDeckKey: includeAddToDeck ? addToDeckKey : null,
                    compareKey: compareKey,
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
    // The coach mark's overlay never settles (see
    // main_screen_tutorial_test.dart), and it shows one step at a time — so
    // these assert on the first step shown.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('starts with the "add to deck" step for a first-time user', (
    tester,
  ) async {
    await pumpTutorial(tester, includeAddToDeck: true);

    expect(find.text('Create a deck'), findsOneWidget);
    expect(find.text('Compare species'), findsNothing);
  });

  testWidgets('shows only the comparison step to a user who has seen the '
      '"add to deck" one', (tester) async {
    await pumpTutorial(tester, includeAddToDeck: false);

    expect(find.text('Compare species'), findsOneWidget);
    expect(find.text('Create a deck'), findsNothing);
  });
}
