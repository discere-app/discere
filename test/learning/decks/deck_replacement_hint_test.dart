import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/deck_replacement_hint.dart';
import 'package:discere/learning/decks/deck_update_hint.dart';
import 'package:discere/learning/decks/service/deck_update_applier.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDeckRepository deckRepository;
  late MockRemoteDeckService remoteDeckService;
  late DeckUpdateService updateService;

  setUp(() {
    deckRepository = MockDeckRepository();
    remoteDeckService = MockRemoteDeckService();
    updateService = DeckUpdateService(deckRepository, remoteDeckService);
    when(deckRepository.getAllDecks()).thenAnswer(
      (_) async => [
        BaseDeck(
          id: 'deck-1',
          name: 'Level 1',
          description: '',
          sourceId: 'level-1',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
  });

  Future<void> pumpHints(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DeckUpdateService>.value(value: updateService),
          Provider<DeckUpdateApplier>.value(
            value: DeckUpdateApplier(
              MockDecksService(),
              MockSpeciesRepository(),
              deprecatedNames: MockDeprecatedSpeciesNameRepository(),
              userDataWrites: UserDataWrites(),
            ),
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
          home: const Scaffold(
            body: Column(
              children: [
                DeckUpdateHint(deckId: 'deck-1'),
                DeckReplacementHint(deckId: 'deck-1'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a superseded deck shows what replaces it, and no update even '
      'when its own entry has one', (tester) async {
    when(remoteDeckService.fetchRemoteDecks()).thenAnswer(
      (_) async => [
        CreateDeck(
          name: 'Level 1',
          description: '',
          sourceId: 'level-1',
          updatedAt: DateTime.utc(2026, 2, 1),
        ),
        CreateDeck(
          name: 'All levels',
          description: '',
          sourceId: 'all',
          supersedes: ['level-1'],
        ),
      ],
    );
    await tester.runAsync(() => updateService.checkForUpdates());

    await pumpHints(tester);

    expect(find.text('Replaced by All levels'), findsOneWidget);
    expect(
      find.byKey(const Key('deck_card_replacement_button_deck-1')),
      findsOneWidget,
    );
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('a deck no entry supersedes shows no replacement', (
    tester,
  ) async {
    when(remoteDeckService.fetchRemoteDecks()).thenAnswer(
      (_) async => [
        CreateDeck(
          name: 'Level 1',
          description: '',
          sourceId: 'level-1',
          updatedAt: DateTime.utc(2026, 2, 1),
        ),
      ],
    );
    await tester.runAsync(() => updateService.checkForUpdates());

    await pumpHints(tester);

    expect(find.textContaining('Replaced by'), findsNothing);
    expect(find.text('Update available'), findsOneWidget);
  });
}
