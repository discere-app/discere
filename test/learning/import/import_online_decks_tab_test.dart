import 'package:discere/catalog/model/species.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/import/import_online_decks_tab.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

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
    final mockDecksService = MockDecksService();
    when(
      mockDecksService.getDecksBySourceId(),
    ).thenAnswer((_) async => {});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LanguageService>.value(
            value: LanguageService(prefs),
          ),
          ChangeNotifierProvider<DecksService>.value(
            value: mockDecksService,
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

  testWidgets(
    'shows an already-imported / update-available status instead of a checkbox for decks already tracked locally',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        LanguageService.sharedPreferencesLanguageKey: Language.en.value,
      });
      final prefs = await SharedPreferences.getInstance();
      final mockDecksService = MockDecksService();
      when(mockDecksService.getDecksBySourceId()).thenAnswer(
        (_) async => {
          'src-up-to-date': BaseDeck(
            'local-1',
            'Local Up To Date',
            'desc',
            sourceId: 'src-up-to-date',
            updatedAt: DateTime.utc(2026, 2, 1),
          ),
          'src-outdated': BaseDeck(
            'local-2',
            'Local Outdated',
            'desc',
            sourceId: 'src-outdated',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        },
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LanguageService>.value(
              value: LanguageService(prefs),
            ),
            ChangeNotifierProvider<DecksService>.value(
              value: mockDecksService,
            ),
          ],
          child: _buildApp(
            ImportOnlineDecksTab(
              loadDecks: () async => [
                CreateDeck(
                  name: 'Not Imported',
                  description: 'desc',
                  speciesNames: {'Amphiprion ocellaris'},
                ),
                CreateDeck(
                  name: 'Up To Date',
                  description: 'desc',
                  speciesNames: {'Chelonia mydas'},
                  sourceId: 'src-up-to-date',
                  updatedAt: DateTime.utc(2026, 1, 1),
                ),
                CreateDeck(
                  name: 'Has Update',
                  description: 'desc',
                  speciesNames: {'Chelonia mydas'},
                  sourceId: 'src-outdated',
                  updatedAt: DateTime.utc(2026, 2, 1),
                ),
              ],
              onImportDecks: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Not yet imported: normal checkbox, no status label.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('deck-checkbox-Not Imported')),
          matching: find.byType(Checkbox),
        ),
        findsOneWidget,
      );
      expect(find.text('Already imported'), findsOneWidget);
      expect(find.text('Update available'), findsOneWidget);

      // Up to date: no checkbox, shows the "already imported" label.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('deck-checkbox-Up To Date')),
          matching: find.byType(Checkbox),
        ),
        findsNothing,
      );

      // Has an update: no checkbox, shows the update-available action instead.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('deck-checkbox-Has Update')),
          matching: find.byType(Checkbox),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('import-online-update-Has Update')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping the update-available action opens the deck-update dialog for '
    'the matched local deck',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        LanguageService.sharedPreferencesLanguageKey: Language.en.value,
      });
      final prefs = await SharedPreferences.getInstance();
      final mockDecksService = MockDecksService();
      final mockSpeciesRepo = MockSpeciesRepository();
      final deckImportService = DeckImportService(
        mockDecksService,
        mockSpeciesRepo,
      );

      when(mockDecksService.getDecksBySourceId()).thenAnswer(
        (_) async => {
          'src-outdated': BaseDeck(
            'local-2',
            'Local Outdated',
            'desc',
            sourceId: 'src-outdated',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        },
      );
      when(
        mockDecksService.getSpeciesByDeckId('local-2'),
      ).thenAnswer((_) async => <Species>[]);
      when(
        mockSpeciesRepo.resolveFullNames(['Chelonia mydas']),
      ).thenAnswer((_) async => {});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LanguageService>.value(
              value: LanguageService(prefs),
            ),
            ChangeNotifierProvider<DecksService>.value(
              value: mockDecksService,
            ),
            Provider<DeckImportService>.value(value: deckImportService),
          ],
          child: _buildApp(
            ImportOnlineDecksTab(
              loadDecks: () async => [
                CreateDeck(
                  name: 'Has Update',
                  description: 'desc',
                  speciesNames: {'Chelonia mydas'},
                  sourceId: 'src-outdated',
                  updatedAt: DateTime.utc(2026, 2, 1),
                ),
              ],
              onImportDecks: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('import-online-update-Has Update')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Deck update available'), findsOneWidget);
    },
  );
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
