import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/decks_view.dart';
import 'package:discere/learning/decks/home_page.dart';
import 'package:discere/learning/favorites/favorites_page.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/view_deck.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../service/mocks.mocks.dart';

class TestFlashcardService extends Fake implements FlashcardService {
  @override
  Future<DeckStat> getDeckStat(String deckId) async => DeckStat(10, 7, 0);
}

class TestINatEnrichmentQueueService extends ChangeNotifier
    implements INatEnrichmentQueueService {
  @override
  INatEnrichmentStatus get status => INatEnrichmentStatus.idle;

  @override
  DeckEnrichmentInfo deckInfo(String deckId) {
    return const DeckEnrichmentInfo(
      status: EnrichmentJobStatus.completed,
      lastCompletedAt: null,
      lastAttemptedAt: null,
    );
  }

  @override
  Future<void> scheduleDeckEnrichment(
    List<String> deckIds, {
    bool includeINatPhotos = true,
    bool includeCommonNames = true,
    Map<String, String?> coverImageUrlsByDeckId = const {},
    Map<String, List<String>> unresolvedNamesByDeckId = const {},
    bool waitForForegroundIdle = false,
  }) async {}

  @override
  void cancelDeckEnrichment(String deckId) {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> enterInteractivePriorityMode() async {}

  @override
  Future<void> leaveInteractivePriorityMode() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Deck progress refresh', () {
    late MockDecksService mockDecksService;
    late TestFlashcardService flashcardService;
    late TestINatEnrichmentQueueService enrichmentQueueService;

    setUp(() {
      mockDecksService = MockDecksService();
      flashcardService = TestFlashcardService();
      enrichmentQueueService = TestINatEnrichmentQueueService();
    });

    testWidgets('HomePage reloads decks when DecksView requests a refresh', (
      WidgetTester tester,
    ) async {
      when(
        mockDecksService.getAllDecks(),
      ).thenAnswer((_) async => [_buildDeck()]);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DecksService>.value(value: mockDecksService),
            ChangeNotifierProvider<FavoriteService>.value(
              value: await _buildFavoriteService(),
            ),
            Provider<FlashcardService>.value(value: flashcardService),
            ChangeNotifierProvider<INatEnrichmentQueueService>.value(
              value: enrichmentQueueService,
            ),
          ],
          child: _buildApp(
            HomePage(
              buildSpeciesDetailPage: (speciesId, language) =>
                  const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final decksView = tester.widget<DecksView>(find.byType(DecksView));

      clearInteractions(mockDecksService);
      decksView.onRefresh?.call();
      await tester.pump();

      verify(mockDecksService.getAllDecks()).called(1);
    });

    testWidgets(
      'FavoritesPage reloads decks when DecksView requests a refresh',
      (WidgetTester tester) async {
        SharedPreferences.setMockInitialValues({
          'favoriteDecks': ['deck-1'],
        });
        final prefs = await SharedPreferences.getInstance();
        final favoriteService = FavoriteService(prefs);

        when(
          mockDecksService.getDecks(any),
        ).thenAnswer((_) async => [_buildDeck()]);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<DecksService>.value(
                value: mockDecksService,
              ),
              ChangeNotifierProvider<FavoriteService>.value(
                value: favoriteService,
              ),
              Provider<FlashcardService>.value(value: flashcardService),
              ChangeNotifierProvider<INatEnrichmentQueueService>.value(
                value: enrichmentQueueService,
              ),
            ],
            child: _buildApp(
              FavoritesPage(
                buildSpeciesDetailPage: (speciesId, language) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final decksView = tester.widget<DecksView>(find.byType(DecksView));

        clearInteractions(mockDecksService);
        decksView.onRefresh?.call();
        await tester.pump();

        verify(mockDecksService.getDecks({'deck-1'})).called(1);
      },
    );
  });
}

ViewDeck _buildDeck() {
  return ViewDeck('deck-1', 'Test Deck', 'Description', 0.3);
}

Future<FavoriteService> _buildFavoriteService() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return FavoriteService(prefs);
}

Widget _buildApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}
