import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/flashcard/deck_page.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/service/spaced_repetition_algorithm.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestFlashcardService implements FlashcardService {
  int getFlashCardsCallCount = 0;
  final NotificationService _notificationService = NotificationService();

  @override
  NotificationService get notificationService => _notificationService;

  @override
  Future<List<SpeciesWithLocalImages>> getFlashCardsForReview(
    String deckId,
  ) async {
    getFlashCardsCallCount++;
    return [_speciesWithImages('sp1')];
  }

  @override
  Future<Map<ReviewGrade, String>> getPreviewIntervals(
    String speciesId,
    String deckId,
  ) async => const {};

  @override
  Future<DeckStat> getDeckStat(String deckId) async => DeckStat(1, 1, 0);

  @override
  Future<void> initializeNextBatch(String deckId, {int batchSize = 10}) async {}

  @override
  Future<void> reviewCard(
    String speciesId,
    String deckId,
    ReviewGrade grade, {
    String? notificationTitle,
    String Function(int count)? notificationBodyBuilder,
  }) async {}

  @override
  Future<List<SpeciesWithLocalImages>> getFlashCardsForSpecies(
    Set<String> species,
  ) async => [_speciesWithImages('sp1')];
}

class TestINatEnrichmentQueueService extends ChangeNotifier
    implements INatEnrichmentQueueService {
  final Map<String, DeckEnrichmentInfo> _deckInfoById = {};

  @override
  INatEnrichmentStatus get status => INatEnrichmentStatus.idle;

  @override
  DeckEnrichmentInfo deckInfo(String deckId) {
    return _deckInfoById[deckId] ??
        const DeckEnrichmentInfo(
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

  void updateDeck(
    String deckId, {
    required EnrichmentJobStatus status,
    required DateTime? lastCompletedAt,
    DateTime? lastAttemptedAt,
  }) {
    _deckInfoById[deckId] = DeckEnrichmentInfo(
      status: status,
      lastCompletedAt: lastCompletedAt,
      lastAttemptedAt: lastAttemptedAt,
    );
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DeckPage reloads flashcards when deck enrichment completes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final watchlistService = WatchlistService(prefs);
    final flashcardService = TestFlashcardService();
    final enrichmentQueueService = TestINatEnrichmentQueueService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FlashcardService>.value(value: flashcardService),
          ChangeNotifierProvider<INatEnrichmentQueueService>.value(
            value: enrichmentQueueService,
          ),
          ChangeNotifierProvider<WatchlistService>.value(
            value: watchlistService,
          ),
        ],
        child: _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(flashcardService.getFlashCardsCallCount, 1);

    enrichmentQueueService.updateDeck(
      'deck-1',
      status: EnrichmentJobStatus.runningForeground,
      lastCompletedAt: null,
      lastAttemptedAt: null,
    );
    await tester.pump();
    expect(flashcardService.getFlashCardsCallCount, 1);

    enrichmentQueueService.updateDeck(
      'deck-1',
      status: EnrichmentJobStatus.completed,
      lastCompletedAt: DateTime(2026, 4, 12, 12),
      lastAttemptedAt: DateTime(2026, 4, 12, 12),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(flashcardService.getFlashCardsCallCount, 2);
  });
}

SpeciesWithLocalImages _speciesWithImages(String id) {
  return SpeciesWithLocalImages(
    Species(
      id,
      id,
      'fishbase',
      'species',
      const {},
      Classification(
        'Genus',
        const {},
        null,
        'Family',
        const {},
        'Order',
        const {},
        'Class',
        const {},
        null,
      ),
      const [],
    ),
    const [],
  );
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
