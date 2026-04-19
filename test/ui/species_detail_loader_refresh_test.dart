import 'package:discere/application/species_media/species_media_service.dart';
import 'package:discere/app/species_detail_loader_page.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../service/mocks.mocks.dart';

class TestINatEnrichmentQueueService extends ChangeNotifier
    implements INatEnrichmentQueueService {
  INatEnrichmentStatus _status = INatEnrichmentStatus.idle;
  final Map<String, DeckEnrichmentInfo> _deckInfoOverrides = {};

  @override
  INatEnrichmentStatus get status => _status;

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
      final speciesMediaService = MockSpeciesMediaService();
      final enrichmentQueueService = TestINatEnrichmentQueueService();
      final decksService = FakeDecksService(
        decksForSpecies: [BaseDeck('deck1', 'Test Deck', 'desc')],
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
            Provider<SourceService>.value(value: FakeSourceService()),
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
}

SpeciesWithLocalImages _speciesWithCommonName(String commonName) {
  return SpeciesWithLocalImages(
    Species(
      'sp1',
      'sp1',
      'fishbase',
      'ocellaris',
      {
        Language.en: [commonName],
      },
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
