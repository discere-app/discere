import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_info.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_state.dart';
import 'package:discere/enrichment/queue/model/enrichment_job.dart';
import 'package:discere/enrichment/queue/model/inat_enrichment_status.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/flashcard/deck_page.dart';
import 'package:discere/learning/flashcard/flashcard_buttons.dart';
import 'package:discere/learning/flashcard/service/deck_session_service.dart';
import 'package:discere/learning/flashcard/service/flashcard_review_service.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/flashcard/service/multiple_choice_distractor_pool_service.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

/// Covers DeckPageState's (lib/learning/flashcard/deck_page.dart) handling
/// of species that don't have a locally downloaded image yet: cards without
/// an image are hidden from the review session while the deck's
/// image-loading enrichment stages are still in flight, an on-demand fetch
/// is triggered when no due card has an image at all, and imageless cards
/// reappear once enrichment gives up trying (permanently no photo found).
class TestFlashcardService extends Fake implements FlashcardService {
  TestFlashcardService({required this.deckConfig});

  final DeckConfig deckConfig;

  @override
  Future<DeckConfig> getDeckConfig(String deckId) async => deckConfig;

  @override
  Future<DeckStat> getDeckStat(String deckId) async => DeckStat(0, 0, 0);

  @override
  Future<void> rescheduleNotifications({
    String? notificationTitle,
    String Function(int count)? notificationBodyBuilder,
  }) async {}
}

class TestFlashcardReviewService extends Fake
    implements FlashcardReviewService {
  TestFlashcardReviewService({
    required List<SpeciesWithLocalImages> flashcards,
  }) : _flashcardsBySpeciesId = {
         for (final card in flashcards) card.species.id: card,
       },
       _order = flashcards.map((card) => card.species.id).toList();

  final Map<String, SpeciesWithLocalImages> _flashcardsBySpeciesId;
  final List<String> _order;

  /// Species id -> what ensureSingleImageForSpecies should return for it.
  /// A non-null result also updates the species' entry so subsequent
  /// getFlashCardsForReview calls reflect the "downloaded" image, mirroring
  /// how the real cache-backed resolution behaves.
  final Map<String, SpeciesWithLocalImages?> imageResultsBySpecies = {};
  final List<String> ensureSingleImageCalls = [];
  final List<(String speciesId, ReviewGrade grade)> reviews = [];

  /// What getUnacknowledgedPhotoGaps should report for this deck — empty by
  /// default so most tests never trigger the gaps dialog.
  List<SpeciesWithLocalImages> unacknowledgedPhotoGaps = const [];
  final List<Set<String>> acknowledgePhotoGapsCalls = [];

  @override
  Future<List<SpeciesWithLocalImages>> getFlashCardsForReview(
    String deckId,
  ) async => _order.map((id) => _flashcardsBySpeciesId[id]!).toList();

  @override
  Future<SpeciesWithLocalImages?> ensureSingleImageForSpecies(
    String speciesId,
  ) async {
    ensureSingleImageCalls.add(speciesId);
    final result = imageResultsBySpecies[speciesId];
    if (result != null) {
      _flashcardsBySpeciesId[speciesId] = result;
    }
    return result;
  }

  // Must be non-empty: DeckPageState.build() re-triggers _loadPreviews()
  // on every build while _previews is empty, so an empty map here spins
  // forever instead of settling.
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
  Future<FlashcardStat> reviewCard(
    String speciesId,
    String deckId,
    ReviewGrade grade,
  ) async {
    reviews.add((speciesId, grade));
    return FlashcardStat(
      speciesId: speciesId,
      deckId: deckId,
      cardState: CardState.review,
    );
  }

  @override
  Future<List<SpeciesWithLocalImages>> getUnacknowledgedPhotoGaps(
    String deckId,
    Set<String> speciesIds,
  ) async => unacknowledgedPhotoGaps;

  @override
  Future<void> acknowledgePhotoGaps(
    String deckId,
    Set<String> speciesIds,
  ) async {
    acknowledgePhotoGapsCalls.add(speciesIds);
  }
}

class TestINatEnrichmentQueueService extends ChangeNotifier
    implements INatEnrichmentQueueService {
  TestINatEnrichmentQueueService({
    this.imageStagesComplete = true,
    this.state = DeckEnrichmentState.done,
    this.includesINatPhotos = false,
  });

  final bool imageStagesComplete;
  final DeckEnrichmentState state;
  final bool includesINatPhotos;

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

  final List<String> scheduleDeckEnrichmentCalls = [];

  @override
  DeckEnrichmentInfo deckInfo(String deckId) => DeckEnrichmentInfo(
    status: EnrichmentJobStatus.completed,
    state: state,
    lastCompletedAt: null,
    lastAttemptedAt: null,
    imageStagesComplete: imageStagesComplete,
    includesINatPhotos: includesINatPhotos,
  );

  @override
  Future<void> scheduleDeckEnrichment(
    List<String> deckIds, {
    bool includeINatPhotos = true,
    bool includeCommonNames = true,
    Map<String, String?> coverImageUrlsByDeckId = const {},
    Map<String, List<String>> unresolvedNamesByDeckId = const {},
    bool waitForForegroundIdle = false,
  }) async {
    scheduleDeckEnrichmentCalls.addAll(deckIds);
  }

  @override
  void cancelDeckEnrichment(String deckId) {}

  @override
  Future<int> countStaleBaseSpeciesGlobally() async => 0;

  @override
  Future<void> refreshStaleBaseImages(String deckId) async {}

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

SpeciesWithLocalImages _flashcard(String id, String genus, String epithet) {
  return SpeciesWithLocalImages(_species(id, genus, epithet), [
    LocalPicture(
      Picture(id: 'pic-$id', species: id, origin: 'inaturalist', isUsable: 1),
      '/tmp/$id.jpg',
    ),
  ]);
}

SpeciesWithLocalImages _flashcardWithoutImage(
  String id,
  String genus,
  String epithet,
) {
  return SpeciesWithLocalImages(_species(id, genus, epithet), const []);
}

Widget _buildApp(
  Widget home, {
  required FlashcardService flashcardService,
  required FlashcardReviewService flashcardReviewService,
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
      Provider<NotificationService>.value(value: NotificationService()),
      Provider<DeckSessionService>.value(
        value: DeckSessionService(
          flashcardReviewService: flashcardReviewService,
          decksService: decksService,
          enrichmentQueueService: enrichmentQueueService,
          distractorPoolService: MultipleChoiceDistractorPoolService(
            taxonomyRepository: MockTaxonomyRepository(),
          ),
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
    when(
      decksService.getSpeciesByDeckId('deck-1'),
    ).thenAnswer((_) async => const []);
  });

  testWidgets(
    'hides due cards without a local image while image-loading enrichment '
    'is still in flight',
    (tester) async {
      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(deckId: 'deck-1', reviewMode: ReviewMode.flip),
      );
      final flashcardReviewService = TestFlashcardReviewService(
        flashcards: [
          _flashcard('sp1', 'Genus1', 'one'),
          _flashcardWithoutImage('sp2', 'Genus2', 'two'),
        ],
      );

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          flashcardReviewService: flashcardReviewService,
          decksService: decksService,
          enrichmentQueueService: TestINatEnrichmentQueueService(
            imageStagesComplete: false,
          ),
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('images_downloading_empty_state_text')),
        findsNothing,
      );
      expect(find.byType(FlashcardButtons), findsOneWidget);
      // sp1 already has an image, so the current-card fetch never triggers,
      // and sp2 is hidden entirely so it's never attempted either.
      expect(flashcardReviewService.ensureSingleImageCalls, isEmpty);

      await tester.tap(find.byIcon(Icons.thumb_up_rounded));
      await tester.pumpAndSettle();

      // Only sp1 was reviewable this session — sp2 stayed hidden.
      expect(flashcardReviewService.reviews, [('sp1', ReviewGrade.easy)]);
    },
  );

  testWidgets(
    'shows a loading state and fetches an image on demand when no due card '
    'has one yet, then reveals the session once it lands',
    (tester) async {
      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(deckId: 'deck-1', reviewMode: ReviewMode.flip),
      );
      final flashcardReviewService = TestFlashcardReviewService(
        flashcards: [
          _flashcardWithoutImage('sp1', 'Genus1', 'one'),
          _flashcardWithoutImage('sp2', 'Genus2', 'two'),
        ],
      );
      flashcardReviewService.imageResultsBySpecies['sp1'] = _flashcard(
        'sp1',
        'Genus1',
        'one',
      );

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          flashcardReviewService: flashcardReviewService,
          decksService: decksService,
          enrichmentQueueService: TestINatEnrichmentQueueService(
            imageStagesComplete: false,
          ),
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      // The on-demand fetch loop found sp1's image and reloaded the
      // session, so the loading state is gone by the time things settle.
      expect(
        find.byKey(const Key('images_downloading_empty_state_text')),
        findsNothing,
      );
      expect(find.byType(FlashcardButtons), findsOneWidget);
      expect(flashcardReviewService.ensureSingleImageCalls, ['sp1']);

      await tester.tap(find.byIcon(Icons.thumb_up_rounded));
      await tester.pumpAndSettle();

      expect(flashcardReviewService.reviews, [('sp1', ReviewGrade.easy)]);
    },
  );

  testWidgets(
    'shows cards without images once image-loading enrichment stages are '
    'complete (deck stays usable even with permanent gaps)',
    (tester) async {
      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(deckId: 'deck-1', reviewMode: ReviewMode.flip),
      );
      final flashcardReviewService = TestFlashcardReviewService(
        flashcards: [
          _flashcard('sp1', 'Genus1', 'one'),
          _flashcardWithoutImage('sp2', 'Genus2', 'two'),
        ],
      );

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          flashcardReviewService: flashcardReviewService,
          decksService: decksService,
          enrichmentQueueService: TestINatEnrichmentQueueService(
            imageStagesComplete: true,
          ),
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.thumb_up_rounded));
      await tester.pumpAndSettle();
      expect(flashcardReviewService.reviews, hasLength(1));

      await tester.tap(find.byIcon(Icons.thumb_up_rounded));
      await tester.pumpAndSettle();
      // Both sp1 and sp2 were reviewable — nothing was filtered out.
      expect(flashcardReviewService.reviews, hasLength(2));
    },
  );

  testWidgets(
    'shows the no-photo-found hint and a remove button on a due card whose '
    'species has no photo',
    (tester) async {
      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(deckId: 'deck-1', reviewMode: ReviewMode.flip),
      );
      final flashcardReviewService = TestFlashcardReviewService(
        flashcards: [
          _flashcard('sp1', 'Genus1', 'one'),
          _flashcardWithoutImage('sp2', 'Genus2', 'two'),
        ],
      );

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          flashcardReviewService: flashcardReviewService,
          decksService: decksService,
          enrichmentQueueService: TestINatEnrichmentQueueService(
            imageStagesComplete: true,
          ),
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      // sp1 is shown first (has an image) — advance to sp2.
      await tester.tap(find.byIcon(Icons.thumb_up_rounded));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remove_species_button')), findsOneWidget);
    },
  );

  testWidgets(
    'removes a species via the inline remove button after confirming',
    (tester) async {
      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(deckId: 'deck-1', reviewMode: ReviewMode.flip),
      );
      final flashcardReviewService = TestFlashcardReviewService(
        flashcards: [
          _flashcard('sp1', 'Genus1', 'one'),
          _flashcardWithoutImage('sp2', 'Genus2', 'two'),
        ],
      );
      when(
        decksService.removeSpeciesFromDeck('deck-1', 'sp2'),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          flashcardReviewService: flashcardReviewService,
          decksService: decksService,
          enrichmentQueueService: TestINatEnrichmentQueueService(
            imageStagesComplete: true,
          ),
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.thumb_up_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remove_species_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove_species_confirm_button')));
      await tester.pumpAndSettle();

      verify(decksService.removeSpeciesFromDeck('deck-1', 'sp2')).called(1);
      // sp2 is gone from the session — no imageless card left to show the
      // remove button on.
      expect(find.byKey(const Key('remove_species_button')), findsNothing);
    },
  );

  testWidgets(
    'offers the no-photo-gaps dialog once enrichment completes with gaps, '
    'and removes checked species',
    (tester) async {
      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(deckId: 'deck-1', reviewMode: ReviewMode.flip),
      );
      final flashcardReviewService = TestFlashcardReviewService(
        flashcards: [_flashcard('sp1', 'Genus1', 'one')],
      );
      flashcardReviewService.unacknowledgedPhotoGaps = [
        _flashcardWithoutImage('sp2', 'Genus2', 'two'),
      ];
      when(
        decksService.removeSpeciesFromDeck('deck-1', 'sp2'),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          flashcardReviewService: flashcardReviewService,
          decksService: decksService,
          enrichmentQueueService: TestINatEnrichmentQueueService(
            imageStagesComplete: true,
            includesINatPhotos: true,
          ),
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('no_photo_gaps_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('no_photo_gap_checkbox_sp2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('no_photo_gaps_confirm_button')));
      await tester.pumpAndSettle();

      verify(decksService.removeSpeciesFromDeck('deck-1', 'sp2')).called(1);
      expect(flashcardReviewService.acknowledgePhotoGapsCalls, isEmpty);
    },
  );

  testWidgets(
    'acknowledges gap species left unchecked in the no-photo-gaps dialog',
    (tester) async {
      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(deckId: 'deck-1', reviewMode: ReviewMode.flip),
      );
      final flashcardReviewService = TestFlashcardReviewService(
        flashcards: [_flashcard('sp1', 'Genus1', 'one')],
      );
      flashcardReviewService.unacknowledgedPhotoGaps = [
        _flashcardWithoutImage('sp2', 'Genus2', 'two'),
      ];

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          flashcardReviewService: flashcardReviewService,
          decksService: decksService,
          enrichmentQueueService: TestINatEnrichmentQueueService(
            imageStagesComplete: true,
            includesINatPhotos: true,
          ),
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      // Leave the checkbox unchecked and confirm — "keep" is the default.
      await tester.tap(find.byKey(const Key('no_photo_gaps_confirm_button')));
      await tester.pumpAndSettle();

      verifyNever(decksService.removeSpeciesFromDeck(any, any));
      expect(flashcardReviewService.acknowledgePhotoGapsCalls, [
        {'sp2'},
      ]);
    },
  );

  testWidgets(
    'offers to start the download instead of checking photo gaps when '
    'nothing was ever downloaded for the deck',
    (tester) async {
      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(deckId: 'deck-1', reviewMode: ReviewMode.flip),
      );
      final flashcardReviewService = TestFlashcardReviewService(
        flashcards: [_flashcard('sp1', 'Genus1', 'one')],
      );

      final enrichmentQueueService = TestINatEnrichmentQueueService(
        imageStagesComplete: true,
        state: DeckEnrichmentState.hidden,
      );

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          flashcardReviewService: flashcardReviewService,
          decksService: decksService,
          enrichmentQueueService: enrichmentQueueService,
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('no_data_downloaded_dialog')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('no_photo_gaps_dialog')), findsNothing);

      await tester.tap(
        find.byKey(const Key('no_data_downloaded_download_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('deck_download_choice_full_button')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('deck_download_choice_base_only_button')),
      );
      await tester.pumpAndSettle();

      expect(enrichmentQueueService.scheduleDeckEnrichmentCalls, ['deck-1']);
    },
  );

  testWidgets(
    'offers to enrich the whole deck for photo gaps when only base data was '
    'downloaded',
    (tester) async {
      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(deckId: 'deck-1', reviewMode: ReviewMode.flip),
      );
      final flashcardReviewService = TestFlashcardReviewService(
        flashcards: [_flashcard('sp1', 'Genus1', 'one')],
      );
      flashcardReviewService.unacknowledgedPhotoGaps = [
        _flashcardWithoutImage('sp2', 'Genus2', 'two'),
      ];

      final enrichmentQueueService = TestINatEnrichmentQueueService(
        imageStagesComplete: true,
        includesINatPhotos: false,
      );

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          flashcardReviewService: flashcardReviewService,
          decksService: decksService,
          enrichmentQueueService: enrichmentQueueService,
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('no_photo_gaps_dialog')), findsOneWidget);
      expect(
        find.byKey(const Key('no_photo_gaps_confirm_button')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('no_photo_gaps_enrich_button')));
      await tester.pumpAndSettle();

      expect(enrichmentQueueService.scheduleDeckEnrichmentCalls, ['deck-1']);
      verifyNever(decksService.removeSpeciesFromDeck(any, any));
    },
  );

  testWidgets(
    'skipping the base-only photo-gaps dialog does not acknowledge the gap '
    'species permanently',
    (tester) async {
      final flashcardService = TestFlashcardService(
        deckConfig: DeckConfig(deckId: 'deck-1', reviewMode: ReviewMode.flip),
      );
      final flashcardReviewService = TestFlashcardReviewService(
        flashcards: [_flashcard('sp1', 'Genus1', 'one')],
      );
      flashcardReviewService.unacknowledgedPhotoGaps = [
        _flashcardWithoutImage('sp2', 'Genus2', 'two'),
      ];

      final enrichmentQueueService = TestINatEnrichmentQueueService(
        imageStagesComplete: true,
        includesINatPhotos: false,
      );

      await tester.pumpWidget(
        _buildApp(
          DeckPage(deck: BaseDeck('deck-1', 'Test Deck', 'Description')),
          flashcardService: flashcardService,
          flashcardReviewService: flashcardReviewService,
          decksService: decksService,
          enrichmentQueueService: enrichmentQueueService,
          watchlistService: watchlistService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('no_photo_gaps_skip_button')));
      await tester.pumpAndSettle();

      expect(enrichmentQueueService.scheduleDeckEnrichmentCalls, isEmpty);
      verifyNever(decksService.removeSpeciesFromDeck(any, any));
      expect(flashcardReviewService.acknowledgePhotoGapsCalls, isEmpty);
    },
  );
}
