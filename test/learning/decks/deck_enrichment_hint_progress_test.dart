import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/deck_enrichment_hint.dart';
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
