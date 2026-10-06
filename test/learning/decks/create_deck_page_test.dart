import 'dart:async';

import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/create_deck_page.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loc = lookupAppLocalizations(const Locale('en'));

  late MockSpeciesRepository speciesRepository;
  late MockDecksService decksService;
  late MockINatEnrichmentQueueService enrichmentQueue;

  setUp(() {
    speciesRepository = MockSpeciesRepository();
    decksService = MockDecksService();
    enrichmentQueue = MockINatEnrichmentQueueService();
    when(speciesRepository.resolveFullNames(any)).thenAnswer(
      (invocation) async => {
        for (final name in invocation.positionalArguments.first as List<String>)
          if (name.startsWith('Carcharodon carcharias')) name: 'species-1',
      },
    );
  });

  /// Pushes the page rather than making it home, so it has a route to pop
  /// back to once the deck is created.
  Future<void> pumpPage(
    WidgetTester tester, {
    String? initialName,
    Set<String>? initialSpeciesNames,
  }) async {
    // Tall enough that the summary below the species field is laid out.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<bool>(
          builder: (_) => CreateDeckPage(
            initialName: initialName,
            initialSpeciesNames: initialSpeciesNames,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final speciesField = find.byKey(const Key('create_deck_species_field'));
  final found = find.byKey(const Key('create_deck_species_found'));
  final notFoundLocally = find.byKey(
    const Key('create_deck_species_not_found_locally'),
  );
  final notSpeciesName = find.byKey(
    const Key('create_deck_species_not_species_name'),
  );

  testWidgets('leaves the species field empty with no initial names', (
    tester,
  ) async {
    await pumpPage(tester);

    final field = tester.widget<TextField>(speciesField);
    expect(field.controller!.text, isEmpty);
    expect(found, findsNothing);
    expect(notFoundLocally, findsNothing);
    expect(notSpeciesName, findsNothing);
  });

  testWidgets('prefills the species field, newline-joined', (tester) async {
    await pumpPage(
      tester,
      initialSpeciesNames: {'Carcharodon carcharias', 'Isurus oxyrinchus'},
    );

    final field = tester.widget<TextField>(speciesField);
    final lines = field.controller!.text.split('\n');
    expect(
      lines,
      unorderedEquals(['Carcharodon carcharias', 'Isurus oxyrinchus']),
    );
  });

  testWidgets('checks a pre-filled list right away', (tester) async {
    await pumpPage(
      tester,
      initialSpeciesNames: {'Carcharodon carcharias', 'Isurus oxyrinchus'},
    );

    expect(find.text(loc.createSpeciesCheckFound(1)), findsOneWidget);
    expect(
      find.text(loc.createSpeciesCheckNotFoundLocally(1, 'Isurus oxyrinchus')),
      findsOneWidget,
    );
  });

  testWidgets('summarizes typed lines once typing pauses', (tester) async {
    await pumpPage(tester);

    await tester.enterText(
      speciesField,
      'Carcharodon carcharias (Linnaeus, 1758)\n'
      'Amphiprion ocelaris\n'
      'Amphiprion',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(found, findsNothing, reason: 'still typing');

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(loc.createSpeciesCheckFound(1)), findsOneWidget);
    expect(
      find.text(
        loc.createSpeciesCheckNotFoundLocally(1, 'Amphiprion ocelaris'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(loc.createSpeciesCheckNotSpeciesName(1, 'Amphiprion')),
      findsOneWidget,
    );
    // Only the lines a lookup can match are looked up.
    verify(
      speciesRepository.resolveFullNames([
        'Carcharodon carcharias (Linnaeus, 1758)',
        'Amphiprion ocelaris',
      ]),
    ).called(1);

    await tester.enterText(speciesField, '');
    await tester.pump(const Duration(milliseconds: 500));
    expect(found, findsNothing);
    expect(notFoundLocally, findsNothing);
    expect(notSpeciesName, findsNothing);
  });

  testWidgets('a late answer for older text does not replace a newer one', (
    tester,
  ) async {
    final slowAnswer = Completer<Map<String, String>>();
    when(
      speciesRepository.resolveFullNames(['Carcharodon carcharias']),
    ).thenAnswer((_) => slowAnswer.future);
    when(
      speciesRepository.resolveFullNames(['Sphyrna mokarran']),
    ).thenAnswer((_) async => {});
    await pumpPage(tester);

    await tester.enterText(speciesField, 'Carcharodon carcharias');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(speciesField, 'Sphyrna mokarran');
    await tester.pump(const Duration(milliseconds: 500));
    slowAnswer.complete({'Carcharodon carcharias': 'species-1'});
    await tester.pumpAndSettle();

    expect(
      find.text(loc.createSpeciesCheckNotFoundLocally(1, 'Sphyrna mokarran')),
      findsOneWidget,
    );
    expect(found, findsNothing);
  });

  testWidgets(
    'creating leaves out non-names and queues unresolved names for iNaturalist',
    (tester) async {
      when(decksService.createDeck(any)).thenAnswer((_) async => 'deck-1');
      await pumpPage(
        tester,
        initialName: 'Sharks',
        initialSpeciesNames: {
          'Carcharodon carcharias',
          'Unknownus fishus',
          'Amphiprion',
        },
      );

      final submit = find.byKey(const ValueKey('create_deck_submit_button'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      // Not pumpAndSettle: the submit button spins until the dialog is
      // answered.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('inat_skip_button')));
      await tester.pumpAndSettle();

      final created =
          verify(decksService.createDeck(captureAny)).captured.single
              as CreateDeck;
      expect(created.speciesNames, {
        'Carcharodon carcharias',
        'Unknownus fishus',
      });
      expect(created.speciesIds, {'species-1'});
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
