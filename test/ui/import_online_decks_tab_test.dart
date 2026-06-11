import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/import/import_online_decks_tab.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('online import supports per-deck language overrides', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LanguageService.sharedPreferencesLanguageKey: Language.en.value,
    });
    final prefs = await SharedPreferences.getInstance();
    List<CreateDeck>? importedDecks;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LanguageService>.value(
            value: LanguageService(prefs),
          ),
        ],
        child: _buildApp(
          ImportOnlineDecksTab(
            loadDecks: () async => [
              CreateDeck(
                name: 'Deck One',
                description: 'desc',
                language: Language.en,
                speciesNames: {'Amphiprion ocellaris'},
              ),
              CreateDeck(
                name: 'Deck Two',
                description: 'desc',
                language: Language.fr,
                speciesNames: {'Chelonia mydas'},
              ),
            ],
            onImportDecks: (selectedDecks) async {
              importedDecks = selectedDecks;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('deck-checkbox-Deck One')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deck-checkbox-Deck Two')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('import-online-language-Deck One')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('German').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('import-online-language-Deck Two')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spanish').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('import-online-button')));
    await tester.pumpAndSettle();

    expect(importedDecks, isNotNull);
    expect(importedDecks, hasLength(2));
    expect(importedDecks![0].name, 'Deck One');
    expect(importedDecks![0].language, Language.de);
    expect(importedDecks![1].name, 'Deck Two');
    expect(importedDecks![1].language, Language.es);
  });
}

Widget _buildApp(Widget home) {
  return MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: home),
  );
}
