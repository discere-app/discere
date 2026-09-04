import 'package:discere/app/reference_db_base_refresh_prompt.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late _FakeINatEnrichmentQueueService enrichmentQueueService;

  setUp(() {
    enrichmentQueueService = _FakeINatEnrichmentQueueService();
  });

  testWidgets(
    'shows nothing when there are no stale base species',
    (tester) async {
      enrichmentQueueService.staleCount = 0;

      await tester.pumpWidget(_buildApp(enrichmentQueueService));
      final dialogContext = tester.element(find.byType(Scaffold));

      await maybeShowBaseRefreshPrompt(dialogContext);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(enrichmentQueueService.refreshAllCalls, 0);
    },
  );

  testWidgets(
    'shows the prompt with the stale count, and "later" declines without '
    'refreshing',
    (tester) async {
      enrichmentQueueService.staleCount = 3;

      await tester.pumpWidget(_buildApp(enrichmentQueueService));
      final dialogContext = tester.element(find.byType(Scaffold));

      final future = maybeShowBaseRefreshPrompt(dialogContext);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('3'),
        findsOneWidget,
        reason: 'the stale count should appear in the message',
      );

      await tester.tap(
        find.byKey(const Key('base_refresh_prompt_later_button')),
      );
      await tester.pumpAndSettle();
      await future;

      expect(enrichmentQueueService.refreshAllCalls, 0);
    },
  );

  testWidgets(
    '"now" triggers refreshAllStaleBaseImages',
    (tester) async {
      enrichmentQueueService.staleCount = 1;

      await tester.pumpWidget(_buildApp(enrichmentQueueService));
      final dialogContext = tester.element(find.byType(Scaffold));

      final future = maybeShowBaseRefreshPrompt(dialogContext);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('base_refresh_prompt_now_button')),
      );
      await tester.pumpAndSettle();
      await future;

      expect(enrichmentQueueService.refreshAllCalls, 1);
    },
  );
}

Widget _buildApp(INatEnrichmentQueueService enrichmentQueueService) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<INatEnrichmentQueueService>.value(
        value: enrichmentQueueService,
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
}

class _FakeINatEnrichmentQueueService extends ChangeNotifier
    implements INatEnrichmentQueueService {
  int staleCount = 0;
  int refreshAllCalls = 0;

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
  Future<int> countStaleBaseSpeciesGlobally() async => staleCount;

  @override
  Future<void> refreshStaleBaseImages(String deckId) async {}

  @override
  Future<void> refreshAllStaleBaseImages() async {
    refreshAllCalls++;
  }

  @override
  Future<void> retriggerBaseEnrichment(String deckId) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> enterInteractivePriorityMode() async {}

  @override
  Future<void> leaveInteractivePriorityMode() async {}
}
