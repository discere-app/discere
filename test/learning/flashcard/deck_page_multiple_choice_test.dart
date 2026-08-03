import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/flashcard/deck_page.dart';
import 'package:discere/learning/flashcard/flashcard_buttons.dart';
import 'package:discere/learning/flashcard/flashcard_multiple_choice_front.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/service/fsrs_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

/// Covers two DeckPageState (lib/learning/flashcard/deck_page.dart) behaviors
/// that had no test coverage: the per-card fallback from multiple-choice to
/// flip mode when a card lacks enough distinct distractors, and the
/// interaction between multiple-choice auto-grading and the
/// learning/relearning re-queue in _gradeCurrentCard.
class TestFlashcardService extends Fake implements FlashcardService {
  TestFlashcardService({
    required this.deckConfig,
    required this.flashcards,
    this.cardStatesBySpecies = const {},
  });

  final DeckConfig deckConfig;
  final List<SpeciesWithLocalImages> flashcards;

  /// Per-species sequence of card states returned by successive reviewCard
  /// calls for that species (e.g. relearning first, then review). The last
  /// entry repeats for any call beyond the sequence's length.
  final Map<String, List<CardState>> cardStatesBySpecies;

  final List<(String speciesId, ReviewGrade grade)> reviews = [];
  final Map<String, int> _reviewCallCounts = {};
  final NotificationService _notificationService = NotificationService();
  int rescheduleNotificationsCallCount = 0;

  @override
  NotificationService get notificationService => _notificationService;

  @override
  Future<DeckConfig> getDeckConfig(String deckId) async => deckConfig;

  @override
  Future<List<SpeciesWithLocalImages>> getFlashCardsForReview(
    String deckId,
  ) async => flashcards;

  // Must be non-empty: DeckPageState.build() re-triggers _loadPreviews()
  // on every build while _previews is empty, so an empty map here spins
  // forever instead of settling (relevant for flip-mode tests only).
  @override
  Future<Map<ReviewGrade, String>> getPreviewIntervals(
    String speciesId,
    String deckId,
  ) async => const {
    ReviewGrade.again: '1m',
    ReviewGrade.hard: '10m',
    ReviewGrade.good: '1d',
    ReviewGrade.easy: '4d',
  };

  @override
  Future<DeckStat> getDeckStat(String deckId) async =>
      DeckStat(flashcards.length, 0, 0);

  @override
  Future<FlashcardStat> reviewCard(
    String speciesId,
    String deckId,
    ReviewGrade grade,
  ) async {
    reviews.add((speciesId, grade));
    final states = cardStatesBySpecies[speciesId] ?? const [CardState.review];
    final callIndex = _reviewCallCounts[speciesId] ?? 0;
    _reviewCallCounts[speciesId] = callIndex + 1;
    final state = callIndex < states.length ? states[callIndex] : states.last;
    return FlashcardStat(
      speciesId: speciesId,
      deckId: deckId,
      cardState: state,
    );
  }

  @override
  Future<void> rescheduleNotifications({
    String? notificationTitle,
    String Function(int count)? notificationBodyBuilder,
  }) async {
    rescheduleNotificationsCallCount++;
  }

  @override
  Future<List<SpeciesWithLocalImages>> getUnacknowledgedPhotoGaps(
    String deckId,
    Set<String> speciesIds,
  ) async => const [];

  @override
  Future<void> acknowledgePhotoGaps(
    String deckId,
    Set<String> speciesIds,
  ) async {}
}

class TestINatEnrichmentQueueService extends ChangeNotifier
    implements INatEnrichmentQueueService {
  @override
  INatEnrichmentStatus get status => INatEnrichmentStatus.idle;

  @override
  DeckEnrichmentInfo deckInfo(String deckId) => const DeckEnrichmentInfo(
    status: EnrichmentJobStatus.completed,
    lastCompletedAt: null,
    lastAttemptedAt: null,
  );

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

Species _species(String id, String genus, String epithet) {
  return Species(
    id,
    id,
    'fishbase',
    epithet,
    const {},
    Classification(
      genus,
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
  );
}

// Binomial name ("$genus $epithet") is used because commonNames is empty
// above, so FlashcardSpeciesPresenter falls back to the scientific name —
// giving each test species a deterministic, distinct primary name without
// needing a Language-keyed common-name map.
SpeciesWithLocalImages _flashcard(String id, String genus, String epithet) {
  return SpeciesWithLocalImages(_species(id, genus, epithet), [
    LocalPicture(
      Picture(id: 'pic-$id', species: id, origin: 'inaturalist', isUsable: 1),
      '/tmp/$id.jpg',
    ),
  ]);
}

Widget _buildApp(
  Widget home, {
  required FlashcardService flashcardService,
  required DecksService decksService,
  required INatEnrichmentQueueService enrichmentQueueService,
  required WatchlistService watchlistService,
  required UserPreferencesService userPreferencesService,
}) {
  return MultiProvider(
    providers: [
      Provider<FlashcardService>.value(value: flashcardService),
      ChangeNotifierProvider<DecksService>.value(value: decksService),
      ChangeNotifierProvider<INatEnrichmentQueueService>.value(
        value: enrichmentQueueService,
      ),
      ChangeNotifierProvider<WatchlistService>.value(value: watchlistService),
      ChangeNotifierProvider<UserPreferencesService>.value(
        value: userPreferencesService,
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
      home: home,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDecksService decksService;
  late WatchlistService watchlistService;
  late UserPreferencesService userPreferencesService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'has_seen_flashcard_tutorial': true,
    });
    final prefs = await SharedPreferences.getInstance();
    decksService = MockDecksService();
    watchlistService = WatchlistService(prefs);
    userPreferencesService = UserPreferencesService(prefs);
  });

  testWidgets(
    'falls back to flip mode for a card whose deck lacks enough distinct '
    'names for multiple choice, even though the deck is configured for it',
    (tester) async {
      // Only 2 distinct names in the whole deck — buildOptions needs 4
      // (1 correct + 3 distractors) and returns null below that.
      final deckSpecies = [
        _species('sp1', 'Genus1', 'one'),
        _species('sp2', 'Genus2', 'two'),
      ];
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => deckSpecies);

      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(
          deckId: 'deck-1',
          reviewMode: ReviewMode.multipleChoice,
        ),
        flashcards: [_flashcard('sp1', 'Genus1', 'one')],
      );

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          decksService: decksService,
          enrichmentQueueService: TestINatEnrichmentQueueService(),
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FlashcardMultipleChoiceFront), findsNothing);
      expect(find.byType(FlashcardButtons), findsOneWidget);
    },
  );

  testWidgets(
    'shows multiple choice for a card with enough distinct deck names',
    (tester) async {
      final deckSpecies = [
        _species('sp1', 'Genus1', 'one'),
        _species('sp2', 'Genus2', 'two'),
        _species('sp3', 'Genus3', 'three'),
        _species('sp4', 'Genus4', 'four'),
      ];
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => deckSpecies);

      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(
          deckId: 'deck-1',
          reviewMode: ReviewMode.multipleChoice,
        ),
        flashcards: [_flashcard('sp1', 'Genus1', 'one')],
      );

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          decksService: decksService,
          enrichmentQueueService: TestINatEnrichmentQueueService(),
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FlashcardMultipleChoiceFront), findsOneWidget);
      expect(find.byType(FlashcardButtons), findsNothing);
      expect(find.text('Genus1 one'), findsOneWidget);
    },
  );

  testWidgets(
    'grading via a multiple-choice tap re-queues a relearning card, which '
    'then reappears in multiple-choice mode again',
    (tester) async {
      final deckSpecies = [
        _species('sp1', 'Genus1', 'one'),
        _species('sp2', 'Genus2', 'two'),
        _species('sp3', 'Genus3', 'three'),
        _species('sp4', 'Genus4', 'four'),
      ];
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => deckSpecies);

      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(
          deckId: 'deck-1',
          reviewMode: ReviewMode.multipleChoice,
        ),
        flashcards: [_flashcard('sp1', 'Genus1', 'one')],
        cardStatesBySpecies: {
          'sp1': [CardState.relearning, CardState.review],
        },
      );

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          decksService: decksService,
          enrichmentQueueService: TestINatEnrichmentQueueService(),
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      // First pass: tapping the correct option grades immediately.
      await tester.tap(find.text('Genus1 one'));
      await tester.pump();

      expect(flashcardService.reviews, [('sp1', ReviewGrade.good)]);

      // Wait for the reveal delay, then advance.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // cardState was relearning, so the same card was re-queued and shows
      // again in multiple-choice mode rather than ending the session.
      expect(find.byType(FlashcardMultipleChoiceFront), findsOneWidget);
      expect(find.text('Genus1 one'), findsOneWidget);

      // Second pass: grading the requeued card again.
      await tester.tap(find.text('Genus1 one'));
      await tester.pump();

      expect(flashcardService.reviews, [
        ('sp1', ReviewGrade.good),
        ('sp1', ReviewGrade.good),
      ]);
    },
  );

  testWidgets(
    'reschedules notifications once when the session ends, not per graded card',
    (tester) async {
      final deckSpecies = [
        _species('sp1', 'Genus1', 'one'),
        _species('sp2', 'Genus2', 'two'),
      ];
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => deckSpecies);

      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(deckId: 'deck-1', reviewMode: ReviewMode.flip),
        flashcards: [
          _flashcard('sp1', 'Genus1', 'one'),
          _flashcard('sp2', 'Genus2', 'two'),
        ],
      );

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          decksService: decksService,
          enrichmentQueueService: TestINatEnrichmentQueueService(),
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      // Grade both cards in the session via the "Easy" flip-mode button.
      await tester.tap(find.byIcon(Icons.thumb_up_rounded));
      await tester.pumpAndSettle();
      expect(flashcardService.reviews, hasLength(1));
      expect(flashcardService.rescheduleNotificationsCallCount, 0);

      await tester.tap(find.byIcon(Icons.thumb_up_rounded));
      await tester.pumpAndSettle();
      expect(flashcardService.reviews, hasLength(2));
      expect(
        flashcardService.rescheduleNotificationsCallCount,
        0,
        reason: 'must not reschedule after every single graded card',
      );

      // Leaving the review session (DeckPage disposed) reschedules once.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(flashcardService.rescheduleNotificationsCallCount, 1);
    },
  );

  testWidgets(
    'does not reschedule notifications if no card was reviewed this session',
    (tester) async {
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => [_species('sp1', 'Genus1', 'one')]);

      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(deckId: 'deck-1', reviewMode: ReviewMode.flip),
        flashcards: [_flashcard('sp1', 'Genus1', 'one')],
      );

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          decksService: decksService,
          enrichmentQueueService: TestINatEnrichmentQueueService(),
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(flashcardService.rescheduleNotificationsCallCount, 0);
    },
  );
}
