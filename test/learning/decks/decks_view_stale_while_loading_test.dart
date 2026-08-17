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

  Future<void> useTallViewport(WidgetTester tester) async {
    final originalSize = tester.view.physicalSize;
    final originalRatio = tester.view.devicePixelRatio;
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalRatio;
    });
  }

  testWidgets(
    'keeps the previous deck list visible while a refreshed future is still loading',
    (tester) async {
      await useTallViewport(tester);
      final favoriteService = await _buildFavoriteService();

      await tester.pumpWidget(
        _buildApp(
          futureDecks: Future.value([_buildDeck('deck-1', 'First Deck')]),
          decksService: decksService,
          favoriteService: favoriteService,
          flashcardService: flashcardService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('First Deck'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Simulate what happens after a deck mutation: DecksService notifies,
      // the host page (HomePage/FavoritesPage) rebuilds and hands DecksView
      // a brand new (still-pending) future.
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
      await tester.pump();

      // No spinner flash, no teardown of the still-valid previous list.
      expect(find.text('First Deck'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      refreshCompleter.complete([
        _buildDeck('deck-1', 'First Deck'),
        _buildDeck('deck-2', 'Second Deck'),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('First Deck'), findsOneWidget);
      expect(find.text('Second Deck'), findsOneWidget);
    },
  );

  testWidgets('shows a spinner only on the very first load', (tester) async {
    final favoriteService = await _buildFavoriteService();
    final initialCompleter = Completer<List<ViewDeck>>();

    await tester.pumpWidget(
      _buildApp(
        futureDecks: initialCompleter.future,
        decksService: decksService,
        favoriteService: favoriteService,
        flashcardService: flashcardService,
        enrichmentQueueService: enrichmentQueueService,
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    initialCompleter.complete([_buildDeck('deck-1', 'First Deck')]);
    await tester.pumpAndSettle();

    expect(find.text('First Deck'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
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
