import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/flashcard/flashcard_image_header.dart';
import 'package:discere/shared/l10n/app_localizations_delegates.dart';
import 'package:discere/shared/ui/image_carousel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

SpeciesWithLocalImages _speciesWithImages(String id) {
  return SpeciesWithLocalImages(_species(id, 'Genus', 'species'), [
    LocalPicture(
      Picture(id: 'pic1', species: id, origin: 'fishbase', isUsable: 1),
      '1.jpg',
    ),
  ]);
}

SpeciesWithLocalImages _speciesWithoutImages(
  String id,
  String genus,
  String epithet,
) {
  return SpeciesWithLocalImages(_species(id, genus, epithet), const []);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WatchlistService watchlistService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    watchlistService = WatchlistService(await SharedPreferences.getInstance());
  });

  Widget buildApp(
    SpeciesWithLocalImages species, {
    Future<void> Function(String speciesId)? onRemoveSpecies,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<WatchlistService>.value(value: watchlistService),
      ],
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FlashcardImageHeader(
            speciesWithLocalImages: species,
            onRemoveSpecies: onRemoveSpecies,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'configures its image carousel to restore all orientations when the '
    'fullscreen viewer closes, since the review flow (DeckPage) keeps '
    'orientation unlocked for its whole session and must not be re-locked '
    'to portrait by a nested fullscreen image view closing',
    (tester) async {
      await tester.pumpWidget(buildApp(_speciesWithImages('sp1')));
      await tester.pumpAndSettle();

      final carousel = tester.widget<ImageCarousel>(find.byType(ImageCarousel));
      expect(
        carousel.restoreOrientationsOnFullscreenClose,
        DeviceOrientation.values,
      );
    },
  );

  testWidgets(
    'does not name the species in the remove confirmation of an imageless '
    'card, since the multiple-choice front asks for that name',
    (tester) async {
      final loc = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(
        buildApp(
          _speciesWithoutImages('sp1', 'Genus1', 'one'),
          onRemoveSpecies: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remove_species_button')));
      await tester.pumpAndSettle();

      final dialog = find.byKey(const Key('remove_species_confirm_dialog'));
      Finder inDialog(Finder finder) =>
          find.descendant(of: dialog, matching: finder);
      expect(inDialog(find.textContaining('Genus1')), findsNothing);
      expect(inDialog(find.textContaining('one')), findsNothing);
      expect(
        inDialog(find.text(loc.flashcardRemoveSpeciesConfirmMessage)),
        findsOneWidget,
      );
    },
  );
}
