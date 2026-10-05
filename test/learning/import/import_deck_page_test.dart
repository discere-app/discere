import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/create_deck_page.dart';
import 'package:discere/learning/import/import_deck_page.dart';
import 'package:discere/learning/import/import_text_recognizer.dart';
import 'package:discere/learning/import/remote_deck_service.dart';
import 'package:discere/learning/service/deck_serialization_worker.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/image_service.dart';
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

  Future<void> pumpTextTab(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      LanguageService.sharedPreferencesLanguageKey: Language.en.value,
    });
    final prefs = await SharedPreferences.getInstance();
    final decksService = MockDecksService();
    when(decksService.getDecksBySourceId()).thenAnswer((_) async => {});
    final remoteDeckService = MockRemoteDeckService();
    when(remoteDeckService.fetchRemoteDecks()).thenAnswer((_) async => []);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LanguageService>.value(
            value: LanguageService(prefs),
          ),
          ChangeNotifierProvider<DecksService>.value(value: decksService),
          Provider<RemoteDeckService>.value(value: remoteDeckService),
          Provider<ImageService>.value(value: MockImageService()),
          Provider<ImportTextRecognizer>.value(
            value: const ImportTextRecognizer(DeckSerializationWorker()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ImportDeckPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import_tab_text')));
    await tester.pumpAndSettle();
  }

  Future<void> importText(WidgetTester tester, String text) async {
    await tester.enterText(
      find.byKey(const ValueKey('import_text_field')),
      text,
    );
    await tester.tap(find.byKey(const ValueKey('import_text_button')));
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, String key) {
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(TextField),
        // The species field carries its key itself, the name field on a
        // wrapper around it.
        matchRoot: true,
      ),
    );
    return field.controller!.text;
  }

  testWidgets('a pasted species list opens Create Deck pre-filled with it', (
    tester,
  ) async {
    await pumpTextTab(tester);

    await importText(
      tester,
      '# Sharks\n- Carcharodon carcharias\n\n- Sphyrna mokarran\n',
    );

    expect(find.byType(CreateDeckPage), findsOneWidget);
    expect(
      fieldText(tester, 'create_deck_species_field'),
      'Carcharodon carcharias\nSphyrna mokarran',
    );
    expect(fieldText(tester, 'create_deck_name_field'), isEmpty);
  });

  testWidgets('unrecognized text shows the format error and stays put', (
    tester,
  ) async {
    await pumpTextTab(tester);

    await importText(tester, 'Hi! Here is my shark deck, have fun.');

    expect(find.byType(CreateDeckPage), findsNothing);
    expect(
      find.text(
        lookupAppLocalizations(const Locale('en')).importFormatUnrecognized,
      ),
      findsOneWidget,
    );
  });
}
