import 'dart:async';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/create_deck_page.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

/// The species the local catalog knows, by id: genus and epithet.
const _catalog = {
  'species-1': ('Carcharodon', 'carcharias'),
  'species-2': ('Prionace', 'glauca'),
  'species-3': ('Sphyrna', 'lewini'),
  'species-4': ('Galeocerdo', 'cuvier'),
};

/// Four species, as many distinct names as multiple choice needs.
const _fourSharks = {
  'Carcharodon carcharias',
  'Prionace glauca',
  'Sphyrna lewini',
  'Galeocerdo cuvier',
};

Species _species(String id) {
  final (genus, epithet) = _catalog[id]!;
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
          for (final MapEntry(key: id, value: (genus, epithet))
              in _catalog.entries)
            if (name.startsWith('$genus $epithet')) name: id,
      },
    );
    when(decksService.getSpeciesByIds(any)).thenAnswer(
      (invocation) async => [
        for (final id in invocation.positionalArguments.first as Set<String>)
          _species(id),
      ],
    );
  });

  /// Pushes the page rather than making it home, so it has a route to pop
  /// back to once the deck is created.
  Future<void> pumpPage(
    WidgetTester tester, {
    String? initialName,
    Set<String>? initialSpeciesNames,
    LearningMode? initialLearningMode,
    NameType? initialNameType,
    ReviewMode? initialReviewMode,
  }) async {
    // Tall enough that everything down to the learning settings is laid out.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ImageService>.value(value: MockImageService()),
          ChangeNotifierProvider<DecksService>.value(value: decksService),
          Provider<DeckImportService>.value(
            value: DeckImportService(
              decksService,
              speciesRepository,
              userDataWrites: UserDataWrites(),
            ),
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
            initialLearningMode: initialLearningMode,
            initialNameType: initialNameType,
            initialReviewMode: initialReviewMode,
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
  final submit = find.byKey(const ValueKey('create_deck_submit_button'));

  Set<LearningMode> learningMode(WidgetTester tester) => tester
      .widget<SegmentedButton<LearningMode>>(
        find.byKey(const Key('learning_mode_segmented_button')),
      )
      .selected;
  Set<NameType> nameType(WidgetTester tester) => tester
      .widget<SegmentedButton<NameType>>(
        find.byKey(const Key('name_type_segmented_button')),
      )
      .selected;
  SegmentedButton<ReviewMode> reviewModeButton(WidgetTester tester) =>
      tester.widget<SegmentedButton<ReviewMode>>(
        find.byKey(const Key('review_mode_segmented_button')),
      );
  bool multipleChoiceEnabled(WidgetTester tester) => reviewModeButton(
    tester,
  ).segments.singleWhere((s) => s.value == ReviewMode.multipleChoice).enabled;

  /// Creates the deck, skipping the iNaturalist offer, and returns what the
  /// page handed to the deck service.
  Future<CreateDeck> create(WidgetTester tester) async {
    when(decksService.createDeck(any)).thenAnswer((_) async => 'deck-1');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    // Not pumpAndSettle: the submit button spins until the dialog is
    // answered.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('inat_skip_button')));
    await tester.pumpAndSettle();
    return verify(decksService.createDeck(captureAny)).captured.single
        as CreateDeck;
  }

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
      await pumpPage(
        tester,
        initialName: 'Sharks',
        initialSpeciesNames: {
          'Carcharodon carcharias',
          'Unknownus fishus',
          'Amphiprion',
        },
      );

      final created = await create(tester);
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

  group('learning settings', () {
    testWidgets('start at the app defaults for a deck made by hand', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(learningMode(tester), {LearningMode.species});
      expect(nameType(tester), {NameType.commonName});
      expect(reviewModeButton(tester).selected, {ReviewMode.flip});
    });

    testWidgets('show the settings an imported deck carries', (tester) async {
      await pumpPage(
        tester,
        initialSpeciesNames: _fourSharks,
        initialLearningMode: LearningMode.genus,
        initialNameType: NameType.scientificName,
        initialReviewMode: ReviewMode.multipleChoice,
      );

      expect(learningMode(tester), {LearningMode.genus});
      expect(nameType(tester), {NameType.scientificName});
      expect(reviewModeButton(tester).selected, {ReviewMode.multipleChoice});
    });

    testWidgets('multiple choice cannot be had for too few distinct names', (
      tester,
    ) async {
      await pumpPage(
        tester,
        initialName: 'Sharks',
        initialSpeciesNames: {'Carcharodon carcharias', 'Prionace glauca'},
        initialReviewMode: ReviewMode.multipleChoice,
      );

      expect(reviewModeButton(tester).selected, {ReviewMode.flip});
      expect(multipleChoiceEnabled(tester), isFalse);
      expect(
        find.text(loc.settingsReviewModeInsufficientSpecies(2)),
        findsOneWidget,
      );
      expect((await create(tester)).reviewMode, ReviewMode.flip);
    });

    testWidgets('an imported multiple choice stands until the first check '
        'has answered', (tester) async {
      final answer = Completer<Map<String, String>>();
      when(speciesRepository.resolveFullNames(any)).thenAnswer(
        (_) => answer.future,
      );
      await pumpPage(
        tester,
        initialSpeciesNames: {'Carcharodon carcharias'},
        initialReviewMode: ReviewMode.multipleChoice,
      );

      expect(reviewModeButton(tester).selected, {ReviewMode.multipleChoice});
      expect(multipleChoiceEnabled(tester), isTrue);

      answer.complete({'Carcharodon carcharias': 'species-1'});
      await tester.pumpAndSettle();

      expect(reviewModeButton(tester).selected, {ReviewMode.flip});
    });

    testWidgets('names taken out and put back bring multiple choice back', (
      tester,
    ) async {
      await pumpPage(
        tester,
        initialSpeciesNames: _fourSharks,
        initialReviewMode: ReviewMode.multipleChoice,
      );

      await tester.enterText(speciesField, 'Carcharodon carcharias');
      await tester.pump(const Duration(milliseconds: 500));
      expect(reviewModeButton(tester).selected, {ReviewMode.flip});

      await tester.enterText(speciesField, _fourSharks.join('\n'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(reviewModeButton(tester).selected, {ReviewMode.multipleChoice});
    });

    testWidgets('the deck is created with the settings chosen', (
      tester,
    ) async {
      await pumpPage(
        tester,
        initialName: 'Sharks',
        initialSpeciesNames: _fourSharks,
        initialLearningMode: LearningMode.genus,
        initialNameType: NameType.scientificName,
      );

      final multipleChoice = find.text(loc.settingsReviewModeMultipleChoice);
      await tester.ensureVisible(multipleChoice);
      await tester.tap(multipleChoice);
      await tester.tap(find.text(loc.settingsLearningModeSpecies));
      await tester.pumpAndSettle();
      final created = await create(tester);

      expect(created.learningMode, LearningMode.species);
      expect(created.nameType, NameType.scientificName);
      expect(created.reviewMode, ReviewMode.multipleChoice);
    });
  });
}
