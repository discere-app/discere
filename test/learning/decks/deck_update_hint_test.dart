import 'package:discere/catalog/model/species.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/deck_update_hint.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDeckRepository mockDeckRepository;
  late MockRemoteDeckService mockRemoteDeckService;
  late MockDecksService mockDecksService;
  late MockSpeciesRepository mockSpeciesRepository;
  late DeckUpdateService deckUpdateService;
  late DeckImportService deckImportService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    mockDeckRepository = MockDeckRepository();
    mockRemoteDeckService = MockRemoteDeckService();
    mockDecksService = MockDecksService();
    mockSpeciesRepository = MockSpeciesRepository();
    deckUpdateService = DeckUpdateService(
      mockDeckRepository,
      mockRemoteDeckService,
      prefs,
    );
    deckImportService = DeckImportService(mockDecksService, mockSpeciesRepository);
  });

  testWidgets('shows nothing when there is no known update for this deck', (
    tester,
  ) async {
    when(
      mockDeckRepository.getAllDecks(),
    ).thenAnswer((_) async => <BaseDeck>[]);

    await tester.pumpWidget(
      _buildApp(
        deckUpdateService: deckUpdateService,
        deckImportService: deckImportService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DeckUpdateHint), findsOneWidget);
    expect(find.text('Update available'), findsNothing);
    expect(find.byIcon(Icons.system_update_alt), findsNothing);
  });

  testWidgets(
    'shows the update row and tapping it opens the diff dialog for this deck',
    (tester) async {
      when(mockDeckRepository.getAllDecks()).thenAnswer(
        (_) async => [
          BaseDeck(
            'deck-1',
            'Local Deck',
            'desc',
            sourceId: 'src-1',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      final remote = CreateDeck(
        name: 'Remote Deck',
        description: 'desc',
        sourceId: 'src-1',
        updatedAt: DateTime.utc(2026, 2, 1),
      );
      when(
        mockRemoteDeckService.fetchRemoteDecks(),
      ).thenAnswer((_) async => [remote]);
      when(
        mockDecksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => <Species>[]);

      await deckUpdateService.checkForUpdates(force: true);

      await tester.pumpWidget(
        _buildApp(
          deckUpdateService: deckUpdateService,
          deckImportService: deckImportService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      expect(find.byIcon(Icons.system_update_alt), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('deck_card_update_button_deck-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Deck update available'), findsOneWidget);
    },
  );
}

Widget _buildApp({
  required DeckUpdateService deckUpdateService,
  required DeckImportService deckImportService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DeckUpdateService>.value(
        value: deckUpdateService,
      ),
      Provider<DeckImportService>.value(value: deckImportService),
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
      home: const Scaffold(body: DeckUpdateHint(deckId: 'deck-1')),
    ),
  );
}
