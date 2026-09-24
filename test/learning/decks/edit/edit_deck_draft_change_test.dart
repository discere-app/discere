import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/edit/edit_deck_page.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../mocks.mocks.dart';
import 'edit_deck_manual_enrichment_test.dart' show TestINatEnrichmentQueueService;

/// Covers EditDeckPage's draft changes going through one path that mutates,
/// re-validates the review mode and re-evaluates the dirty state together.
///
/// The three used to be written out at each call site, so a change that
/// skipped one left the page in a state that looks right on screen: a save
/// button that stays inactive, or a review mode the deck can no longer
/// support.

Species _species(String id, String scientificName) => Species(
  id,
  scientificName,
  'fishbase',
  scientificName,
  const {},
  Classification(
    scientificName.split(' ').first,
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
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDecksService decksService;
  late MockImageService imageService;
  late MockNotificationService notificationService;
  late MockFlashcardService flashcardService;
  late TestINatEnrichmentQueueService enrichmentQueueService;
  late UserPreferencesService userPreferencesService;

  setUp(() async {
    decksService = MockDecksService();
    imageService = MockImageService();
    notificationService = MockNotificationService();
    flashcardService = MockFlashcardService();
    enrichmentQueueService = TestINatEnrichmentQueueService();
    // The coach mark never settles once shown, which would hang every
    // pumpAndSettle here — same reason as the enrichment tests next door.
    SharedPreferences.setMockInitialValues({
      'has_seen_edit_deck_tutorial': true,
    });
    userPreferencesService = UserPreferencesService(
      await SharedPreferences.getInstance(),
    );

    when(
      notificationService.shouldPromptForPermission(),
    ).thenAnswer((_) async => false);
    when(decksService.updateDeck(any, any)).thenAnswer((_) async {});
    when(flashcardService.getDeckConfig(any)).thenAnswer(
      (inv) async => DeckConfig(
        deckId: inv.positionalArguments.first as String,
        desiredRetention: 0.9,
        reviewMode: ReviewMode.multipleChoice,
      ),
    );
  });

  SegmentedButton<ReviewMode> reviewModeButton(WidgetTester tester) =>
      tester.widget<SegmentedButton<ReviewMode>>(
        find.byKey(const Key('review_mode_segmented_button')),
      );

  Future<SegmentedButton<ReviewMode>> pumpAndFindReviewMode(
    WidgetTester tester,
  ) async {
    // Tall enough for the whole page: the species list and the learning
    // settings are then on screen together, so neither has to be scrolled
    // into view — and a lazy list never drops the rows this test taps.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DecksService>.value(value: decksService),
          Provider<ImageService>.value(value: imageService),
          Provider<NotificationService>.value(value: notificationService),
          Provider<FlashcardService>.value(value: flashcardService),
          ChangeNotifierProvider<INatEnrichmentQueueService>.value(
            value: enrichmentQueueService,
          ),
          ChangeNotifierProvider<UserPreferencesService>.value(
            value: userPreferencesService,
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
          home: EditDeckPage(
            deck: BaseDeck(
              'deck-1',
              'Test Deck',
              'Description',
              language: Language.en,
            ),
            buildSpeciesDetailPage: (speciesId, language) =>
                const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return reviewModeButton(tester);
  }

  bool multipleChoiceEnabled(SegmentedButton<ReviewMode> button) => button
      .segments
      .firstWhere((segment) => segment.value == ReviewMode.multipleChoice)
      .enabled;

  testWidgets('four distinct names make multiple choice selectable', (
    tester,
  ) async {
    when(decksService.getSpeciesByDeckId('deck-1')).thenAnswer(
      (_) async => [
        _species('sp1', 'Amphiprion ocellaris'),
        _species('sp2', 'Dascyllus aruanus'),
        _species('sp3', 'Chromis viridis'),
        _species('sp4', 'Premnas biaculeatus'),
      ],
    );

    expect(multipleChoiceEnabled(await pumpAndFindReviewMode(tester)), isTrue);
  });

  testWidgets(
    'removing a species below the threshold disables multiple choice again',
    (tester) async {
      when(decksService.getSpeciesByDeckId('deck-1')).thenAnswer(
        (_) async => [
          _species('sp1', 'Amphiprion ocellaris'),
          _species('sp2', 'Dascyllus aruanus'),
          _species('sp3', 'Chromis viridis'),
          _species('sp4', 'Premnas biaculeatus'),
        ],
      );
      expect(multipleChoiceEnabled(await pumpAndFindReviewMode(tester)), isTrue);

      // Removing a species is a draft change like any other: it has to
      // re-validate, or the deck keeps a review mode it can no longer serve.
      // Found by tooltip because the deck-delete button carries the same
      // icon as a species row's.
      await tester.tap(find.byTooltip('Remove').first);
      await tester.pumpAndSettle();

      expect(multipleChoiceEnabled(reviewModeButton(tester)), isFalse);
    },
  );
}
