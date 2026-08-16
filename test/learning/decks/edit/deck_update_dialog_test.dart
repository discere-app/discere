import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/edit/deck_update_dialog.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../../mocks.mocks.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'apply button becomes enabled as soon as the diff loads, with no extra interaction needed',
    (tester) async {
      final mockDecksService = MockDecksService();
      final mockSpeciesRepo = MockSpeciesRepository();
      final deckImportService = DeckImportService(
        mockDecksService,
        mockSpeciesRepo,
      );

      when(
        mockDecksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => <Species>[]);
      when(
        mockSpeciesRepo.resolveFullNames(['New Species']),
      ).thenAnswer((_) async => {'New Species': 'id-new'});
      when(mockDecksService.getSpeciesByIds({'id-new'})).thenAnswer(
        (_) async => [_species('id-new', 'Genus', 'new')],
      );

      final remote = CreateDeck(
        name: 'Remote Deck',
        description: 'desc',
        speciesNames: {'New Species'},
        sourceId: 'src-1',
        updatedAt: DateTime.utc(2026, 2, 1),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DeckImportService>.value(value: deckImportService),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () =>
                      showDeckUpdateDialog(context, 'deck-1', remote),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('deck_update_apply_button')),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason:
            'Apply should be enabled once the diff has loaded, without '
            'needing an unrelated interaction (e.g. toggling a checkbox) '
            'to force a rebuild.',
      );
    },
  );

  testWidgets(
    'accepting the iNat enrichment offer after apply actually schedules it',
    (tester) async {
      final mockDecksService = MockDecksService();
      final mockSpeciesRepo = MockSpeciesRepository();
      final mockNotificationService = MockNotificationService();
      final enrichmentQueueService = TestINatEnrichmentQueueService();
      final deckImportService = DeckImportService(
        mockDecksService,
        mockSpeciesRepo,
      );

      when(
        mockDecksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => <Species>[]);
      when(
        mockSpeciesRepo.resolveFullNames(['New Species']),
      ).thenAnswer((_) async => {'New Species': 'id-new'});
      when(mockDecksService.getSpeciesByIds({'id-new'})).thenAnswer(
        (_) async => [_species('id-new', 'Genus', 'new')],
      );
      when(mockDecksService.getCreateDeck('deck-1')).thenAnswer(
        (_) async => CreateDeck(
          id: 'deck-1',
          name: 'Local Deck',
          description: 'desc',
          speciesIds: const {},
          sourceId: 'src-old',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      when(mockDecksService.updateDeck(any, any)).thenAnswer((_) async {});
      when(
        mockNotificationService.shouldPromptForPermission(),
      ).thenAnswer((_) async => false);

      final remote = CreateDeck(
        name: 'Remote Deck',
        description: 'desc',
        speciesNames: {'New Species'},
        sourceId: 'src-1',
        updatedAt: DateTime.utc(2026, 2, 1),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DeckImportService>.value(value: deckImportService),
            ChangeNotifierProvider<DeckUpdateService>.value(
              value: DeckUpdateService(
                MockDeckRepository(),
                MockRemoteDeckService(),
                MockSharedPreferences(),
              ),
            ),
            ChangeNotifierProvider<INatEnrichmentQueueService>.value(
              value: enrichmentQueueService,
            ),
            Provider<NotificationService>.value(
              value: mockNotificationService,
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
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () =>
                      showDeckUpdateDialog(context, 'deck-1', remote),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Can't pumpAndSettle from here: the update dialog stays open with its
      // Apply button mid-spinner (indeterminate CircularProgressIndicator,
      // which animates forever) while _apply() awaits the user's answer to
      // the iNat download dialog below — pumpAndSettle would time out
      // waiting for that animation to stop.
      await tester.tap(find.byKey(const Key('deck_update_apply_button')));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The unconditional (reference-image / name-resolution) call always
      // fires once species were added.
      expect(enrichmentQueueService.calls, hasLength(1));
      expect(find.byKey(const Key('inat_download_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('inat_download_button')));
      await tester.pumpAndSettle();

      // The user accepted the iNat photos/common-names offer — this is the
      // call that used to get silently dropped because the dialog's
      // context was already torn down by an earlier Navigator.pop().
      expect(enrichmentQueueService.calls, hasLength(2));
      final secondCall = enrichmentQueueService.calls[1];
      expect(secondCall.includeINatPhotos, isTrue);
      expect(secondCall.includeCommonNames, isTrue);
      expect(secondCall.deckIds, ['deck-1']);
    },
  );
}

class TestINatEnrichmentQueueService extends ChangeNotifier
    implements INatEnrichmentQueueService {
  final List<EnrichmentScheduleCall> calls = [];

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
