import 'dart:async';

import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/decks_view.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/view_deck.dart';
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
  Future<DeckStat> getDeckStat(String deckId) async => DeckStat(1, 1, 0);
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

  /// Fires a listener notification like a live queue-state refresh would,
  /// rebuilding every DeckCard's enrichment Selector.
  void emitQueueRefresh() => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDecksService decksService;
  late TestFlashcardService flashcardService;
  late TestINatEnrichmentQueueService enrichmentQueueService;

  setUp(() {
    decksService = MockDecksService();
    flashcardService = TestFlashcardService();
    enrichmentQueueService = TestINatEnrichmentQueueService();
  });

  testWidgets(
    'dismissed deck leaves the tree immediately and survives rebuilds while '
    'the async delete is still in flight',
    (tester) async {
      final favoriteService = await _buildFavoriteService();
      // The delete stays pending for the whole test — the dismissed card must
      // be gone from the tree anyway, purely from local state.
      final deleteCompleter = Completer<void>();
      when(
        decksService.deleteDeck('deck-1'),
      ).thenAnswer((_) => deleteCompleter.future);

      await tester.pumpWidget(
        _buildApp(
          futureDecks: Future.value([
            _buildDeck('deck-1', 'First Deck'),
            _buildDeck('deck-2', 'Second Deck'),
          ]),
          decksService: decksService,
          favoriteService: favoriteService,
          flashcardService: flashcardService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('First Deck'), findsOneWidget);

      await tester.drag(find.text('First Deck'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_deck_confirm_button')));
      await tester.pumpAndSettle();

      // Dismissible contract: the widget must be out of the tree by now even
      // though the database delete has not completed.
      expect(find.text('First Deck'), findsNothing);
      expect(find.text('Second Deck'), findsOneWidget);
      verify(decksService.deleteDeck('deck-1')).called(1);

      // The real-world crash path: any service notification makes the host
      // page rebuild and hand DecksView a brand-new, still-pending future.
      // DecksView then renders its retained snapshot — which used to still
      // contain the dismissed deck, re-inserting the dismissed Dismissible
      // and throwing "A dismissed Dismissible widget is still part of the
      // tree".
      final refreshCompleter = Completer<List<ViewDeck>>();
      await tester.pumpWidget(
        _buildApp(
          futureDecks: refreshCompleter.future,
          decksService: decksService,
          favoriteService: favoriteService,
          flashcardService: flashcardService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      enrichmentQueueService.emitQueueRefresh();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('First Deck'), findsNothing);
      expect(find.text('Second Deck'), findsOneWidget);

      // Deletion confirmed: the fresh load no longer contains the deck.
      deleteCompleter.complete();
      refreshCompleter.complete([_buildDeck('deck-2', 'Second Deck')]);
      await tester.pumpAndSettle();

      expect(find.text('First Deck'), findsNothing);
      expect(find.text('Second Deck'), findsOneWidget);
    },
  );
}

ViewDeck _buildDeck(String id, String name) {
  return ViewDeck(id, name, 'Description', 0.3);
}

Future<FavoriteService> _buildFavoriteService() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return FavoriteService(prefs);
}

Widget _buildApp({
  required Future<List<ViewDeck>> futureDecks,
  required DecksService decksService,
  required FavoriteService favoriteService,
  required FlashcardService flashcardService,
  required INatEnrichmentQueueService enrichmentQueueService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DecksService>.value(value: decksService),
      ChangeNotifierProvider<FavoriteService>.value(value: favoriteService),
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
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: DecksView(
        futureDecks,
        buildSpeciesDetailPage: (speciesId, language) =>
            const SizedBox.shrink(),
      ),
    ),
  );
}
