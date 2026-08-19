import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/deck_enrichment_hint.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _TestINatEnrichmentQueueService enrichmentQueueService;

  setUp(() {
    enrichmentQueueService = _TestINatEnrichmentQueueService();
  });

  group('DeckEnrichmentHint progress display', () {
    testWidgets(
      'shows no progress number while the deck is not yet ready '
      '(loadingBase), even though a species-level total already exists',
      (tester) async {
        enrichmentQueueService.setInfo(
          'deck-1',
          const DeckEnrichmentInfo(
            state: DeckEnrichmentState.loadingBase,
            status: EnrichmentJobStatus.runningForeground,
            lastCompletedAt: null,
            lastAttemptedAt: null,
            progressCompleted: 3,
            progressTotal: 10,
          ),
        );

        await tester.pumpWidget(_buildApp(enrichmentQueueService));
        await tester.pumpAndSettle();

        expect(find.text('Loading base data …'), findsOneWidget);
        expect(find.textContaining('%'), findsNothing);
        expect(find.textContaining('3'), findsNothing);
        expect(find.textContaining('10'), findsNothing);
      },
    );

    testWidgets(
      'shows a percentage once the deck is ready and still being '
      'supplemented (loadingExtended)',
      (tester) async {
        enrichmentQueueService.setInfo(
          'deck-1',
          const DeckEnrichmentInfo(
            state: DeckEnrichmentState.loadingExtended,
            status: EnrichmentJobStatus.runningForeground,
            lastCompletedAt: null,
            lastAttemptedAt: null,
            progressCompleted: 13,
            progressTotal: 18,
          ),
        );

        await tester.pumpWidget(_buildApp(enrichmentQueueService));
        await tester.pumpAndSettle();

        // 13/18 rounds to 72%.
        expect(find.textContaining('72%'), findsOneWidget);
      },
    );

    testWidgets(
      'falls back to the plain loadingExtended label when there is no '
      'progress total yet',
      (tester) async {
        enrichmentQueueService.setInfo(
          'deck-1',
          const DeckEnrichmentInfo(
            state: DeckEnrichmentState.loadingExtended,
            status: EnrichmentJobStatus.runningForeground,
            lastCompletedAt: null,
            lastAttemptedAt: null,
          ),
        );

        await tester.pumpWidget(_buildApp(enrichmentQueueService));
        await tester.pumpAndSettle();

        expect(find.text('Ready – still adding data'), findsOneWidget);
        expect(find.textContaining('%'), findsNothing);
      },
    );

    testWidgets(
      'shows nothing for a done deck once sessionCompletedAt is gone '
      '(e.g. after a restart) — not a generic "enrichment complete" label',
      (tester) async {
        enrichmentQueueService.setInfo(
          'deck-1',
          const DeckEnrichmentInfo(
            state: DeckEnrichmentState.done,
            status: EnrichmentJobStatus.completed,
            lastCompletedAt: null,
            lastAttemptedAt: null,
            sessionCompletedAt: null,
          ),
        );

        await tester.pumpWidget(_buildApp(enrichmentQueueService));
        await tester.pumpAndSettle();

        expect(find.text('Enrichment complete'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(DeckEnrichmentHint),
            matching: find.byType(Text),
          ),
          findsNothing,
          reason: 'a settled done deck should show nothing, not a generic '
              'status label, once there is no session-specific info left',
        );
      },
    );

    testWidgets(
      'shows the relative-time label for a done deck while '
      'sessionCompletedAt is still set (just finished this session)',
      (tester) async {
        enrichmentQueueService.setInfo(
          'deck-1',
          DeckEnrichmentInfo(
            state: DeckEnrichmentState.done,
            status: EnrichmentJobStatus.completed,
            lastCompletedAt: DateTime.now(),
            lastAttemptedAt: null,
            sessionCompletedAt: DateTime.now(),
          ),
        );

        await tester.pumpWidget(_buildApp(enrichmentQueueService));
        await tester.pumpAndSettle();

        expect(find.text('Last updated just now'), findsOneWidget);
      },
    );

    testWidgets(
      'mentions that names may have changed when the completed run '
      'included common-name enrichment',
      (tester) async {
        enrichmentQueueService.setInfo(
          'deck-1',
          DeckEnrichmentInfo(
            state: DeckEnrichmentState.done,
            status: EnrichmentJobStatus.completed,
            lastCompletedAt: DateTime.now(),
            lastAttemptedAt: null,
            sessionCompletedAt: DateTime.now(),
            includesCommonNames: true,
          ),
        );

        await tester.pumpWidget(_buildApp(enrichmentQueueService));
        await tester.pumpAndSettle();

        expect(
          find.text('Last updated just now · names may have been refined'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'does not mention names when the completed run was photo-only',
      (tester) async {
        enrichmentQueueService.setInfo(
          'deck-1',
          DeckEnrichmentInfo(
            state: DeckEnrichmentState.done,
            status: EnrichmentJobStatus.completed,
            lastCompletedAt: DateTime.now(),
            lastAttemptedAt: null,
            sessionCompletedAt: DateTime.now(),
            includesCommonNames: false,
          ),
        );

        await tester.pumpWidget(_buildApp(enrichmentQueueService));
        await tester.pumpAndSettle();

        expect(find.text('Last updated just now'), findsOneWidget);
      },
    );
  });
}

Widget _buildApp(INatEnrichmentQueueService enrichmentQueueService) {
  return MultiProvider(
    providers: [
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
      home: const Scaffold(body: DeckEnrichmentHint(deckId: 'deck-1')),
    ),
  );
}

class _TestINatEnrichmentQueueService extends ChangeNotifier
    implements INatEnrichmentQueueService {
  final Map<String, DeckEnrichmentInfo> _deckInfoById = {};

  @override
  INatEnrichmentStatus get status => INatEnrichmentStatus.idle;

  @override
  HostCooldownSnapshot? get activeCooldown => null;

  @override
  Future<bool> get isForegroundServiceRunning async => false;

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

  @override
  Future<void> enterInteractivePriorityMode() async {}

  @override
  Future<void> leaveInteractivePriorityMode() async {}

  void setInfo(String deckId, DeckEnrichmentInfo info) {
    _deckInfoById[deckId] = info;
    notifyListeners();
  }
}
