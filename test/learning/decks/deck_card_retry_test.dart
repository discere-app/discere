import 'package:discere/enrichment/queue/model/deck_enrichment_info.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_state.dart';
import 'package:discere/enrichment/queue/model/enrichment_job.dart';
import 'package:discere/enrichment/queue/model/inat_enrichment_status.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/deck_card.dart';
import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';
import '../../support/persisted_warnings.dart';

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
        expect(enrichmentQueueService.calls.single.includeINatPhotos, isTrue);
        expect(enrichmentQueueService.calls.single.includeCommonNames, isFalse);
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

  group('DeckCard failures reach the diagnostics log', () {
    const failedInfo = DeckEnrichmentInfo(
      state: DeckEnrichmentState.failed,
      status: EnrichmentJobStatus.failedPermanent,
      lastCompletedAt: null,
      lastAttemptedAt: null,
      includesINatPhotos: true,
      includesCommonNames: true,
    );

    testWidgets('a failed deck stat load is logged once, however often the '
        'card rebuilds, and the subtitle still shows nothing', (tester) async {
      final warnings = recordPersistedWarnings();
      when(
        flashcardService.getDeckStat(any),
      ).thenAnswer((_) => Future.error(StateError('stat broken')));

      await tester.pumpWidget(
        _buildApp(
          flashcardService: flashcardService,
          notificationService: notificationService,
          enrichmentQueueService: enrichmentQueueService,
        ),
      );
      await tester.pumpAndSettle();
      // Rebuilds every widget with the same future in place: whatever shows
      // the error builds again, nothing fetches again.
      // The reassembly completes with the frame it schedules, so that frame
      // is pumped before it is awaited.
      final reassembled = tester.binding.reassembleApplication();
      await tester.pumpAndSettle();
      await reassembled;

      expect(warnings, hasLength(1));
      expect(
        warnings.single,
        startsWith(
          '[DeckCard] Deck stat load failed — StateError: Bad state: stat '
          'broken',
        ),
      );
      // The stack trace, as Logger indents it, down to where the card asked.
      expect(warnings.single, contains('\n    '));
      expect(warnings.single, contains('_DeckCardState._fetchDeckStat'));
      expect(find.textContaining('learned'), findsNothing);
    });

    testWidgets('a failed retry shows its snack bar and is logged with its '
        'stack trace', (tester) async {
      final warnings = recordPersistedWarnings();
      enrichmentQueueService
        ..setInfo('deck-1', failedInfo)
        ..scheduleFailure = StateError('schedule broken');

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

      final loc = lookupAppLocalizations(const Locale('en'));
      expect(
        find.text(loc.editDeckINatEnrichmentError(loc.errorGeneric)),
        findsOneWidget,
      );
      expect(warnings, hasLength(1));
      expect(
        warnings.single,
        startsWith(
          '[DeckEnrichmentHint] Deck enrichment retry failed — StateError: '
          'Bad state: schedule broken',
        ),
      );
      expect(warnings.single, contains('\n    '));
      expect(warnings.single, contains('_DeckEnrichmentHintState._retry'));
    });
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
      ChangeNotifierProvider<DeckUpdateService>.value(
        value: DeckUpdateService(
          MockDeckRepository(),
          MockRemoteDeckService(),
          MockSharedPreferences(),
        ),
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
              deck: DeckViewModel(
                stored: BaseDeck(
                  id: 'deck-1',
                  name: 'Test Deck',
                  description: 'Description',
                ),
                progress: 0.5,
              ),
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

  /// Thrown by [scheduleDeckEnrichment] once the call is recorded, when set.
  Object? scheduleFailure;

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
    if (scheduleFailure case final failure?) throw failure;
  }

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
