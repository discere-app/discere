import 'package:discere/enrichment/queue/model/deck_enrichment_info.dart';
import 'package:discere/enrichment/queue/model/enrichment_job.dart';
import 'package:discere/enrichment/queue/model/inat_enrichment_status.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/learning/decks/decks_content.dart';
import 'package:discere/learning/decks/decks_tab.dart';
import 'package:discere/learning/favorites/favorites_tab.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

class TestFlashcardService extends Fake implements FlashcardService {
  @override
  Future<DeckStat> getDeckStat(String deckId) async => DeckStat(10, 7, 0);
}

class TestINatEnrichmentQueueService extends ChangeNotifier
    implements INatEnrichmentQueueService {
  @override
  INatEnrichmentStatus get status => INatEnrichmentStatus.idle;

  @override
  HostCooldownSnapshot? get activeCooldown => null;

  @override
  Future<bool> get isForegroundServiceRunning async => false;

  @override
  Future<Set<String>> pendingCommonNameSpeciesIds(Set<String> speciesIds) async {
    return {};
  }

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
  Future<int> countStaleBaseSpeciesGlobally() async => 0;

  @override
  Future<void> refreshStaleBaseImages(String deckId) async {}

  @override
  Future<void> shutdown() async {}

  @override
  Future<void> refreshAllStaleBaseImages() async {}

  @override
  Future<void> retriggerBaseEnrichment(String deckId) async {}

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

    testWidgets('DecksTab reloads decks when DecksContent requests a refresh', (
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
            ChangeNotifierProvider<DeckUpdateService>.value(
              value: DeckUpdateService(
                MockDeckRepository(),
                MockRemoteDeckService(),
                MockSharedPreferences(),
              ),
            ),
          ],
          child: _buildApp(
            DecksTab(
              buildSpeciesDetailPage: (speciesId, language) =>
                  const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final decksContent = tester.widget<DecksContent>(
        find.byType(DecksContent),
      );

      clearInteractions(mockDecksService);
      decksContent.onRefresh?.call();
      await tester.pump();

      verify(mockDecksService.getAllDecks()).called(1);
    });

    testWidgets(
      'FavoritesTab reloads decks when DecksContent requests a refresh',
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
              ChangeNotifierProvider<DeckUpdateService>.value(
                value: DeckUpdateService(
                  MockDeckRepository(),
                  MockRemoteDeckService(),
                  MockSharedPreferences(),
                ),
              ),
            ],
            child: _buildApp(
              FavoritesTab(
                buildSpeciesDetailPage: (speciesId, language) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final decksContent = tester.widget<DecksContent>(
          find.byType(DecksContent),
        );

        clearInteractions(mockDecksService);
        decksContent.onRefresh?.call();
        await tester.pump();

        verify(mockDecksService.getDecks({'deck-1'})).called(1);
      },
    );
  });

  group('What makes a deck tab load its decks again', () {
    late _CountingDecksService decksService;
    late FavoriteService favoriteService;
    late ValueNotifier<int> rebuildFromAbove;

    setUp(() async {
      decksService = _CountingDecksService();
      SharedPreferences.setMockInitialValues({
        'favoriteDecks': ['deck-1'],
      });
      favoriteService = FavoriteService(await SharedPreferences.getInstance());
      rebuildFromAbove = ValueNotifier(0);
    });

    Future<void> pumpTab(WidgetTester tester, Widget Function() tab) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DecksService>.value(value: decksService),
            ChangeNotifierProvider<FavoriteService>.value(
              value: favoriteService,
            ),
            Provider<FlashcardService>.value(value: TestFlashcardService()),
            ChangeNotifierProvider<INatEnrichmentQueueService>.value(
              value: TestINatEnrichmentQueueService(),
            ),
            ChangeNotifierProvider<DeckUpdateService>.value(
              value: DeckUpdateService(
                MockDeckRepository(),
                MockRemoteDeckService(),
                MockSharedPreferences(),
              ),
            ),
          ],
          // A fresh tab widget on every tick, as the main screen hands out
          // on a tab switch.
          child: _buildApp(
            ValueListenableBuilder<int>(
              valueListenable: rebuildFromAbove,
              builder: (_, _, _) => tab(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Widget decksTab() => DecksTab(
      buildSpeciesDetailPage: (speciesId, language) => const SizedBox.shrink(),
    );

    Widget favoritesTab() => FavoritesTab(
      buildSpeciesDetailPage: (speciesId, language) => const SizedBox.shrink(),
    );

    testWidgets('DecksTab: a rebuild from above reloads, so the due counts '
        'follow a tab switch; so does a deck change', (tester) async {
      await pumpTab(tester, decksTab);
      expect(decksService.loads, 1);

      rebuildFromAbove.value++;
      await tester.pumpAndSettle();
      expect(decksService.loads, 2);

      decksService.notifyDecksChanged();
      await tester.pumpAndSettle();
      expect(decksService.loads, 3);
    });

    testWidgets('FavoritesTab: a rebuild from above reloads, so the due '
        'counts follow a tab switch; so do a deck change and a favorite '
        'toggle', (tester) async {
      await pumpTab(tester, favoritesTab);
      expect(decksService.loads, 1);

      rebuildFromAbove.value++;
      await tester.pumpAndSettle();
      expect(decksService.loads, 2);

      decksService.notifyDecksChanged();
      await tester.pumpAndSettle();
      expect(decksService.loads, 3);

      favoriteService.toggleDeck('deck-2');
      await tester.pumpAndSettle();
      expect(decksService.loads, 4);
      expect(decksService.lastRequestedIds, {'deck-1', 'deck-2'});
    });
  });
}

DeckViewModel _buildDeck() {
  return DeckViewModel(
    stored: BaseDeck(
      id: 'deck-1',
      name: 'Test Deck',
      description: 'Description',
    ),
    progress: 0.3,
  );
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


/// A [DecksService] that notifies like the real one and counts list loads.
/// Everything else is unused here.
class _CountingDecksService extends ChangeNotifier implements DecksService {
  int loads = 0;
  Set<String>? lastRequestedIds;

  @override
  Future<List<DeckViewModel>> getAllDecks() async {
    loads++;
    return [_buildDeck()];
  }

  @override
  Future<List<DeckViewModel>> getDecks(Set<String> deckIds) async {
    loads++;
    lastRequestedIds = deckIds;
    return [_buildDeck()];
  }

  @override
  void notifyDecksChanged() => notifyListeners();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
