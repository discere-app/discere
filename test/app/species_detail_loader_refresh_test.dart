import 'package:discere/app/species_detail_loader_page.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_info.dart';
import 'package:discere/enrichment/queue/model/enrichment_job.dart';
import 'package:discere/enrichment/queue/model/inat_enrichment_status.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/navigation_tab_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

class TestINatEnrichmentQueueService extends ChangeNotifier
    implements INatEnrichmentQueueService {
  INatEnrichmentStatus _status = INatEnrichmentStatus.idle;
  final Map<String, DeckEnrichmentInfo> _deckInfoOverrides = {};

  @override
  INatEnrichmentStatus get status => _status;

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
    return _deckInfoOverrides[deckId] ??
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

  void setDeckInfo(String deckId, DeckEnrichmentInfo info) {
    _deckInfoOverrides[deckId] = info;
  }

  void updateStatus(INatEnrichmentStatus status) {
    _status = status;
    notifyListeners();
  }
}

class FakeDecksService extends ChangeNotifier implements DecksService {
  final List<BaseDeck> decksForSpecies;

  FakeDecksService({this.decksForSpecies = const []});

  @override
  Future<List<BaseDeck>> getDecksForSpecies(String speciesId) async {
    return decksForSpecies;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSourceService extends Fake implements SourceService {
  @override
  Future<List<Source>> getAllSources() async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'SpeciesDetailLoaderPage reloads cached species after queue completion',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final languageService = LanguageService(prefs);
      final watchlistService = WatchlistService(prefs);
      final speciesMediaService = MockSpeciesMediaService();
      final enrichmentQueueService = TestINatEnrichmentQueueService();
      final decksService = FakeDecksService(
        decksForSpecies: [BaseDeck(id: 'deck1', name: 'Test Deck', description: 'desc')],
      );

      var resolveFromCacheCallCount = 0;
      when(
        speciesMediaService.hasEnrichedPhotos('sp1'),
      ).thenAnswer((_) async => true);
      when(speciesMediaService.resolveFromCache('sp1')).thenAnswer((_) async {
        resolveFromCacheCallCount++;
        return resolveFromCacheCallCount == 1
            ? _speciesWithCommonName('Old name')
            : _speciesWithCommonName('New name');
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SpeciesMediaService>.value(value: speciesMediaService),
            ChangeNotifierProvider<INatEnrichmentQueueService>.value(
              value: enrichmentQueueService,
            ),
            ChangeNotifierProvider<DecksService>.value(value: decksService),
            ChangeNotifierProvider<LanguageService>.value(
              value: languageService,
            ),
            ChangeNotifierProvider<WatchlistService>.value(
              value: watchlistService,
            ),
            Provider<SourceService>.value(value: FakeSourceService()),
            ChangeNotifierProvider<NavigationTabService>(
              create: (_) => NavigationTabService(),
            ),
          ],
          child: _buildApp(const SpeciesDetailLoaderPage(speciesId: 'sp1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Old name'), findsWidgets);
      expect(resolveFromCacheCallCount, 1);

      // Simulate enrichment starting for this deck
      enrichmentQueueService.setDeckInfo(
        'deck1',
        const DeckEnrichmentInfo(
          status: EnrichmentJobStatus.runningForeground,
          lastCompletedAt: null,
          lastAttemptedAt: null,
        ),
      );
      enrichmentQueueService.updateStatus(
        const INatEnrichmentStatus(
          isRunning: true,
          hasPendingWork: true,
          hasActiveWork: true,
          hasActiveHostCooldown: false,
          phase: INatEnrichmentPhase.names,
          completed: 0,
          total: 1,
        ),
      );
      await tester.pump();

      // Simulate enrichment completing for this deck
      final completedAt = DateTime.now();
      enrichmentQueueService.setDeckInfo(
        'deck1',
        DeckEnrichmentInfo(
          status: EnrichmentJobStatus.completed,
          lastCompletedAt: completedAt,
          lastAttemptedAt: completedAt,
        ),
      );
      enrichmentQueueService.updateStatus(INatEnrichmentStatus.idle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('New name'), findsWidgets);
      expect(resolveFromCacheCallCount, 2);
    },
  );

  testWidgets(
    'SpeciesDetailLoaderPage keeps the language picked for the names when '
    'it reloads the species after queue completion',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        LanguageService.sharedPreferencesLanguageKey: Language.en.value,
      });
      final prefs = await SharedPreferences.getInstance();
      final speciesMediaService = MockSpeciesMediaService();
      final enrichmentQueueService = TestINatEnrichmentQueueService();

      var resolveFromCacheCallCount = 0;
      when(
        speciesMediaService.hasEnrichedPhotos('sp1'),
      ).thenAnswer((_) async => true);
      when(speciesMediaService.resolveFromCache('sp1')).thenAnswer((_) async {
        resolveFromCacheCallCount++;
        return _speciesWithCommonNames({
          Language.en: const ['Clown anemonefish'],
          Language.de: [
            resolveFromCacheCallCount == 1 ? 'Alter Name' : 'Neuer Name',
          ],
        });
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SpeciesMediaService>.value(value: speciesMediaService),
            ChangeNotifierProvider<INatEnrichmentQueueService>.value(
              value: enrichmentQueueService,
            ),
            ChangeNotifierProvider<DecksService>.value(
              value: FakeDecksService(
                decksForSpecies: [
                  BaseDeck(id: 'deck1', name: 'Test Deck', description: 'desc'),
                ],
              ),
            ),
            ChangeNotifierProvider<LanguageService>.value(
              value: LanguageService(prefs),
            ),
            ChangeNotifierProvider<WatchlistService>.value(
              value: WatchlistService(prefs),
            ),
            Provider<SourceService>.value(value: FakeSourceService()),
            ChangeNotifierProvider<NavigationTabService>(
              create: (_) => NavigationTabService(),
            ),
          ],
          child: _buildApp(const SpeciesDetailLoaderPage(speciesId: 'sp1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('German'));
      await tester.pumpAndSettle();

      expect(find.text('Alter Name'), findsWidgets);

      // A completion the loader has not seen yet makes it reload.
      final completedAt = DateTime.now();
      enrichmentQueueService.setDeckInfo(
        'deck1',
        DeckEnrichmentInfo(
          status: EnrichmentJobStatus.completed,
          lastCompletedAt: completedAt,
          lastAttemptedAt: completedAt,
        ),
      );
      enrichmentQueueService.updateStatus(INatEnrichmentStatus.idle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(resolveFromCacheCallCount, 2);
      expect(find.text('DE'), findsOneWidget);
      expect(find.text('Neuer Name'), findsWidgets);
      expect(find.text('Clown anemonefish'), findsNothing);
    },
  );
}

SpeciesWithLocalImages _speciesWithCommonName(String commonName) =>
    _speciesWithCommonNames({
      Language.en: [commonName],
    });

SpeciesWithLocalImages _speciesWithCommonNames(
  Map<Language, List<String>> commonNames,
) {
  return SpeciesWithLocalImages(
    Species(
      'sp1',
      'sp1',
      'fishbase',
      'ocellaris',
      commonNames,
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
