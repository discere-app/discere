import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/edit/edit_deck_page.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EditDeckPage manual iNaturalist enrichment', () {
    late MockDecksService decksService;
    late MockImageService imageService;
    late MockNotificationService notificationService;
    late MockFlashcardService flashcardService;
    late TestINatEnrichmentQueueService enrichmentQueueService;

    setUp(() {
      decksService = MockDecksService();
      imageService = MockImageService();
      notificationService = MockNotificationService();
      flashcardService = MockFlashcardService();
      enrichmentQueueService = TestINatEnrichmentQueueService();

      when(
        notificationService.shouldPromptForPermission(),
      ).thenAnswer((_) async => false);
      when(decksService.updateDeck(any, any)).thenAnswer((_) async {});
      when(flashcardService.getDeckConfig(any)).thenAnswer(
        (inv) async => DeckConfig(
          deckId: inv.positionalArguments.first as String,
          desiredRetention: 0.9,
        ),
      );
    });

    testWidgets('shows never enriched state when only base enrichment exists', (
      tester,
    ) async {
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => [_species('sp1')]);
      enrichmentQueueService.setInfo(
        'deck-1',
        DeckEnrichmentInfo(
          status: EnrichmentJobStatus.completed,
          lastCompletedAt: DateTime(2026, 4, 12, 12),
          lastAttemptedAt: DateTime(2026, 4, 12, 12),
          includesINatPhotos: false,
          includesCommonNames: false,
        ),
      );

      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollToManualSection(tester);

      expect(find.text('iNaturalist Enrichment'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Not enriched with iNaturalist yet'), findsOneWidget);
      expect(find.text('Enrich now'), findsOneWidget);
    });

    testWidgets('shows last iNaturalist enrichment timestamp', (tester) async {
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => [_species('sp1')]);
      enrichmentQueueService.setInfo(
        'deck-1',
        DeckEnrichmentInfo(
          status: EnrichmentJobStatus.completed,
          lastCompletedAt: DateTime(2026, 4, 12, 12, 30),
          lastAttemptedAt: DateTime(2026, 4, 12, 12, 30),
          includesINatPhotos: true,
          includesCommonNames: true,
        ),
      );

      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollToManualSection(tester);

      expect(find.textContaining('Last enriched:'), findsOneWidget);
      expect(find.text('Enrich again'), findsOneWidget);
    });

    testWidgets(
      'saves current edits before scheduling iNaturalist enrichment',
      (tester) async {
        when(
          decksService.getSpeciesByDeckId('deck-1'),
        ).thenAnswer((_) async => [_species('sp1')]);

        await tester.pumpWidget(
          _buildApp(
            decksService: decksService,
            imageService: imageService,
            notificationService: notificationService,
            flashcardService: flashcardService,
            enrichmentQueueService: enrichmentQueueService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('edit_deck_name_field')),
          'Updated Deck',
        );
        await _scrollToManualSection(tester);
        await tester.tap(
          find.byKey(const Key('edit_deck_inat_enrichment_button')),
        );
        await tester.pumpAndSettle();

        final captured = verify(
          decksService.updateDeck(captureAny, captureAny),
        ).captured;
        final savedDeck = captured[0] as BaseDeck;
        final savedSpeciesIds = captured[1] as Set<String>;
        expect(savedDeck.name, 'Updated Deck');
        expect(savedSpeciesIds, {'sp1'});
        expect(enrichmentQueueService.calls, hasLength(1));
        expect(enrichmentQueueService.calls.single.deckIds, ['deck-1']);
        expect(enrichmentQueueService.calls.single.includeINatPhotos, isTrue);
        expect(enrichmentQueueService.calls.single.includeCommonNames, isTrue);
      },
    );

    testWidgets('disables button while enrichment has pending work', (
      tester,
    ) async {
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => [_species('sp1')]);
      enrichmentQueueService.setInfo(
        'deck-1',
        const DeckEnrichmentInfo(
          status: EnrichmentJobStatus.runningForeground,
          lastCompletedAt: null,
          lastAttemptedAt: null,
          includesINatPhotos: true,
          includesCommonNames: true,
        ),
      );

      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollToManualSection(tester);

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('edit_deck_inat_enrichment_button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('shows active enrichment progress as species count', (
      tester,
    ) async {
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => [_species('sp1')]);
      enrichmentQueueService.setInfo(
        'deck-1',
        const DeckEnrichmentInfo(
          status: EnrichmentJobStatus.runningForeground,
          lastCompletedAt: null,
          lastAttemptedAt: null,
          includesINatPhotos: true,
          includesCommonNames: true,
          progressCompleted: 3,
          progressTotal: 10,
        ),
      );

      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollToManualSection(tester);

      expect(find.text('Loading (3 / 10 species)'), findsOneWidget);
    });

    testWidgets('shows ready status while additional enrichment continues', (
      tester,
    ) async {
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => [_species('sp1')]);
      enrichmentQueueService.setInfo(
        'deck-1',
        const DeckEnrichmentInfo(
          status: EnrichmentJobStatus.queued,
          lastCompletedAt: null,
          lastAttemptedAt: null,
          includesINatPhotos: true,
          includesCommonNames: true,
          isReady: true,
        ),
      );

      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollToManualSection(tester);

      expect(find.text('Loading …'), findsOneWidget);
    });

    testWidgets(
      'shows phase label while enrichment is in retryScheduled state',
      (tester) async {
        when(
          decksService.getSpeciesByDeckId('deck-1'),
        ).thenAnswer((_) async => [_species('sp1')]);
        enrichmentQueueService.setInfo(
          'deck-1',
          DeckEnrichmentInfo(
            status: EnrichmentJobStatus.retryScheduled,
            lastCompletedAt: null,
            lastAttemptedAt: DateTime(2026, 4, 25, 9, 0),
            includesINatPhotos: true,
            includesCommonNames: true,
          ),
        );

        await tester.pumpWidget(
          _buildApp(
            decksService: decksService,
            imageService: imageService,
            notificationService: notificationService,
            flashcardService: flashcardService,
            enrichmentQueueService: enrichmentQueueService,
          ),
        );
        await tester.pumpAndSettle();
        await _scrollToManualSection(tester);

        expect(find.text('Loading …'), findsOneWidget);
      },
    );

    testWidgets('enables save only after an edit', (tester) async {
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => [_species('sp1')]);

      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      await tester.pumpAndSettle();

      final initialSaveButton = tester.widget<TextButton>(
        find.byKey(const Key('edit_deck_save_button')),
      );
      expect(initialSaveButton.onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('edit_deck_name_field')),
        'Updated Deck',
      );
      await tester.pump();

      final editedSaveButton = tester.widget<TextButton>(
        find.byKey(const Key('edit_deck_save_button')),
      );
      expect(editedSaveButton.onPressed, isNotNull);
    });

    testWidgets('keeps button enabled after a failed enrichment attempt', (
      tester,
    ) async {
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => [_species('sp1')]);
      enrichmentQueueService.setInfo(
        'deck-1',
        const DeckEnrichmentInfo(
          status: EnrichmentJobStatus.failedTemporary,
          lastCompletedAt: null,
          lastAttemptedAt: null,
          includesINatPhotos: true,
          includesCommonNames: true,
        ),
      );

      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollToManualSection(tester);

      expect(
        find.text('Last enrichment failed. You can try again.'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('edit_deck_inat_enrichment_button')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('disables button for decks without species', (tester) async {
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => const []);

      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollToManualSection(tester);

      expect(
        find.text('Add species before starting enrichment.'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('edit_deck_inat_enrichment_button')),
      );
      expect(button.onPressed, isNull);
    });
  });
}

Future<void> _scrollToManualSection(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('edit_deck_inat_enrichment_button')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Widget _buildApp({
  required DecksService decksService,
  required ImageService imageService,
  required NotificationService notificationService,
  required FlashcardService flashcardService,
  required INatEnrichmentQueueService enrichmentQueueService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DecksService>.value(value: decksService),
      Provider<ImageService>.value(value: imageService),
      Provider<NotificationService>.value(value: notificationService),
      Provider<FlashcardService>.value(value: flashcardService),
      ChangeNotifierProvider<INatEnrichmentQueueService>.value(
        value: enrichmentQueueService,
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: EditDeckPage(
        deck: BaseDeck(
          'deck-1',
          'Test Deck',
          'Description',
          language: Language.en,
        ),
        buildSpeciesDetailPage: (speciesId, language) =>
            const SizedBox.shrink(),
      ),
    ),
  );
}

class TestINatEnrichmentQueueService extends ChangeNotifier
    implements INatEnrichmentQueueService {
  final Map<String, DeckEnrichmentInfo> _deckInfoById = {};
  final List<EnrichmentScheduleCall> calls = [];

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
  }) async {
    calls.add(
      EnrichmentScheduleCall(
        deckIds: deckIds,
        includeINatPhotos: includeINatPhotos,
        includeCommonNames: includeCommonNames,
      ),
    );
  }

  @override
  void cancelDeckEnrichment(String deckId) {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> enterInteractivePriorityMode() async {}

  @override
  Future<void> leaveInteractivePriorityMode() async {}

  void setInfo(String deckId, DeckEnrichmentInfo info) {
    _deckInfoById[deckId] = info;
    notifyListeners();
  }
}

class EnrichmentScheduleCall {
  final List<String> deckIds;
  final bool includeINatPhotos;
  final bool includeCommonNames;

  const EnrichmentScheduleCall({
    required this.deckIds,
    required this.includeINatPhotos,
    required this.includeCommonNames,
  });
}

Species _species(String id) {
  return Species(
    id,
    'Amphiprion ocellaris',
    'fishbase',
    'species',
    const {},
    Classification(
      'Amphiprion',
      const {},
      null,
      'Pomacentridae',
      const {},
      'Perciformes',
      const {},
      'Actinopterygii',
      const {},
      null,
    ),
    const [],
  );
}
