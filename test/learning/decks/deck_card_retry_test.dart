import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/deck_card.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/view_deck.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFlashcardService flashcardService;
  late MockNotificationService notificationService;
  late TestINatEnrichmentQueueService enrichmentQueueService;

  setUp(() {
    flashcardService = MockFlashcardService();
    notificationService = MockNotificationService();
    enrichmentQueueService = TestINatEnrichmentQueueService();

    when(
      flashcardService.getDeckStat(any),
    ).thenAnswer((_) async => DeckStat(1, 1, 0));
    when(
      notificationService.shouldPromptForPermission(),
    ).thenAnswer((_) async => false);
  });

  group('DeckCard retry CTA for failed enrichment', () {
    testWidgets('shows a retry button when enrichment failed permanently', (
      tester,
    ) async {
      enrichmentQueueService.setInfo(
        'deck-1',
        const DeckEnrichmentInfo(
          state: DeckEnrichmentState.failed,
          status: EnrichmentJobStatus.failedPermanent,
          lastCompletedAt: null,
          lastAttemptedAt: null,
          includesINatPhotos: true,
          includesCommonNames: true,
        ),
      );

      await tester.pumpWidget(
        _buildApp(
          flashcardService: flashcardService,
          notificationService: notificationService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('deck_card_inat_retry_button_deck-1')),
        findsOneWidget,
      );
    });

    testWidgets('does not show a retry button while enrichment is loading', (
      tester,
    ) async {
      enrichmentQueueService.setInfo(
        'deck-1',
        const DeckEnrichmentInfo(
          state: DeckEnrichmentState.loadingBase,
          status: EnrichmentJobStatus.runningForeground,
          lastCompletedAt: null,
          lastAttemptedAt: null,
          includesINatPhotos: true,
          includesCommonNames: true,
        ),
      );

      await tester.pumpWidget(
        _buildApp(
          flashcardService: flashcardService,
          notificationService: notificationService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('deck_card_inat_retry_button_deck-1')),
        findsNothing,
      );
    });

    testWidgets(
      'tapping retry reschedules enrichment with the previous flags',
      (tester) async {
        enrichmentQueueService.setInfo(
          'deck-1',
          const DeckEnrichmentInfo(
            state: DeckEnrichmentState.failed,
            status: EnrichmentJobStatus.failedPermanent,
            lastCompletedAt: null,
            lastAttemptedAt: null,
            includesINatPhotos: true,
            includesCommonNames: false,
          ),
        );

        await tester.pumpWidget(
          _buildApp(
            flashcardService: flashcardService,
            notificationService: notificationService,
            enrichmentQueueService: enrichmentQueueService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('deck_card_inat_retry_button_deck-1')),
        );
        await tester.pumpAndSettle();

        expect(enrichmentQueueService.calls, hasLength(1));
        expect(enrichmentQueueService.calls.single.deckIds, ['deck-1']);
        expect(
          enrichmentQueueService.calls.single.includeINatPhotos,
          isTrue,
        );
        expect(
          enrichmentQueueService.calls.single.includeCommonNames,
          isFalse,
        );
      },
    );

    testWidgets(
      'shows the notification permission prompt before retrying if needed',
      (tester) async {
        when(
          notificationService.shouldPromptForPermission(),
        ).thenAnswer((_) async => true);
        when(
          notificationService.declinePermissionPrompt(),
        ).thenAnswer((_) async {});
        enrichmentQueueService.setInfo(
          'deck-1',
          const DeckEnrichmentInfo(
            state: DeckEnrichmentState.failed,
            status: EnrichmentJobStatus.failedPermanent,
            lastCompletedAt: null,
            lastAttemptedAt: null,
            includesINatPhotos: true,
            includesCommonNames: true,
          ),
        );

        await tester.pumpWidget(
          _buildApp(
            flashcardService: flashcardService,
            notificationService: notificationService,
            enrichmentQueueService: enrichmentQueueService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('deck_card_inat_retry_button_deck-1')),
        );
        // The retry button shows a spinner while awaiting the permission
        // dialog, whose animation never settles on its own — pump discrete
        // frames instead of pumpAndSettle() until the dialog is up.
        await tester.pump();
        await tester.pump();

        expect(
          find.byKey(const Key('notification_permission_dialog')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const Key('notification_permission_skip_button')),
        );
        await tester.pumpAndSettle();

        verify(notificationService.declinePermissionPrompt()).called(1);
        expect(enrichmentQueueService.calls, hasLength(1));
        expect(enrichmentQueueService.calls.single.deckIds, ['deck-1']);
      },
    );
  });
}

Widget _buildApp({
  required FlashcardService flashcardService,
  required NotificationService notificationService,
  required INatEnrichmentQueueService enrichmentQueueService,
}) {
  return MultiProvider(
    providers: [
      Provider<FlashcardService>.value(value: flashcardService),
      Provider<NotificationService>.value(value: notificationService),
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
      home: Scaffold(
        body: ListView(
          children: [
            DeckCard(
              deck: ViewDeck('deck-1', 'Test Deck', 'Description', 0.5),
              isFavorite: false,
              onFavoriteToggle: () {},
              onTap: () {},
              onEdit: () {},
              onShare: () {},
              onDismiss: () {},
            ),
          ],
        ),
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
