import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/edit/edit_deck_page.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../mocks.mocks.dart';
import 'edit_deck_manual_enrichment_test.dart'
    show TestINatEnrichmentQueueService;

/// Covers EditDeckPage handing its species to the list that resolves their
/// images. How that list resolves, refreshes and survives a failure is
/// edit_deck_species_list_test.dart's subject; this is the one thing it cannot
/// see — that the page's rows are that list's rows, fed with the deck's
/// species.

void main() {
  testWidgets('a deck species without a reference picture shows its cached '
      'iNat photo', (tester) async {
    final species = Species(
      'sp1',
      'sp1',
      'fishbase',
      'ocellaris',
      const {},
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
    );
    const iNatPhoto = Picture(
      id: 'inat-sp1',
      species: 'sp1',
      url: 'https://inat/sp1.jpg',
      origin: 'iNaturalist',
      isUsable: 1,
    );

    final decksService = MockDecksService();
    final flashcardService = MockFlashcardService();
    final speciesMediaService = MockSpeciesMediaService();
    when(
      decksService.getSpeciesByDeckId('deck-1'),
    ).thenAnswer((_) async => [species]);
    when(flashcardService.getDeckConfig('deck-1')).thenAnswer(
      (_) async => DeckConfig(deckId: 'deck-1', desiredRetention: 0.9),
    );
    when(speciesMediaService.resolveSpeciesFromCache([species])).thenAnswer(
      (_) async => [
        SpeciesWithLocalImages(species, [
          LocalPicture(iNatPhoto, '/inat/sp1.jpg'),
        ]),
      ],
    );
    // The coach mark never settles once shown, which would hang pumpAndSettle.
    SharedPreferences.setMockInitialValues({
      'has_seen_edit_deck_tutorial': true,
    });
    final userPreferencesService = UserPreferencesService(
      await SharedPreferences.getInstance(),
    );

    // Tall enough for the whole page, so the lazy list below the settings
    // sections builds its row.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DecksService>.value(value: decksService),
          Provider<ImageService>.value(value: MockImageService()),
          Provider<FlashcardService>.value(value: flashcardService),
          Provider<SpeciesMediaService>.value(value: speciesMediaService),
          ChangeNotifierProvider<INatEnrichmentQueueService>.value(
            value: TestINatEnrichmentQueueService(),
          ),
          ChangeNotifierProvider<UserPreferencesService>.value(
            value: userPreferencesService,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EditDeckPage(
            deck: BaseDeck(
              id: 'deck-1',
              name: 'Test Deck',
              description: 'Description',
              language: Language.en,
            ),
            buildSpeciesDetailPage: (speciesId, language) =>
                const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = tester.widget<SpeciesListItem>(
      find.byKey(const ValueKey('sp1')),
    );
    expect(row.item.localImagePath, '/inat/sp1.jpg');
  });
}
