import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/create_deck_page.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp({Set<String>? initialSpeciesNames}) {
    return Provider<ImageService>.value(
      value: ImageService(
        client: http.Client(),
        hostCooldownTracker: HostCooldownTracker(),
      ),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CreateDeckPage(initialSpeciesNames: initialSpeciesNames),
      ),
    );
  }

  testWidgets('leaves the species field empty with no initial names', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());

    final field = tester.widget<TextField>(
      find.byKey(const Key('create_deck_species_field')),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('prefills the species field, newline-joined', (tester) async {
    await tester.pumpWidget(
      buildApp(
        initialSpeciesNames: {'Carcharodon carcharias', 'Isurus oxyrinchus'},
      ),
    );

    final field = tester.widget<TextField>(
      find.byKey(const Key('create_deck_species_field')),
    );
    final lines = field.controller!.text.split('\n');
    expect(
      lines,
      unorderedEquals(['Carcharodon carcharias', 'Isurus oxyrinchus']),
    );
  });

  testWidgets(
    'names that do not resolve locally are shown and queued for iNaturalist',
    (tester) async {
      final speciesRepository = MockSpeciesRepository();
      final decksService = MockDecksService();
      final enrichmentQueue = MockINatEnrichmentQueueService();
      when(
        speciesRepository.resolveFullNames(any),
      ).thenAnswer((_) async => {'Carcharodon carcharias': 'species-1'});
      when(decksService.createDeck(any)).thenAnswer((_) async => 'deck-1');
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ImageService>.value(value: MockImageService()),
            Provider<DeckImportService>.value(
              value: DeckImportService(decksService, speciesRepository),
            ),
            ChangeNotifierProvider<INatEnrichmentQueueService>.value(
              value: enrichmentQueue,
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SizedBox.shrink(),
          ),
        ),
      );
      // Pushed rather than set as home, so the page has a route to pop back
      // to once the deck is created.
      navigatorKey.currentState!.push(
        MaterialPageRoute<bool>(
          builder: (_) => const CreateDeckPage(
            initialName: 'Sharks',
            initialSpeciesNames: {'Carcharodon carcharias', 'Unknownus fishus'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final submit = find.byKey(const ValueKey('create_deck_submit_button'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      // Not pumpAndSettle: the submit button spins until the dialog is
      // answered.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('inat_download_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('inat_skip_button')));
      await tester.pumpAndSettle();

      verify(
        enrichmentQueue.scheduleDeckEnrichment(
          ['deck-1'],
          includeINatPhotos: false,
          includeCommonNames: false,
          coverImageUrlsByDeckId: {},
          unresolvedNamesByDeckId: {
            'deck-1': ['Unknownus fishus'],
          },
        ),
      ).called(1);
      expect(find.byType(CreateDeckPage), findsNothing);
    },
  );
}
