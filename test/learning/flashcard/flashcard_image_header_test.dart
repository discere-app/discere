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

SpeciesWithLocalImages _speciesWithImages(String id) {
  return SpeciesWithLocalImages(
    Species(
      id,
      id,
      'fishbase',
      'species',
      const {},
      Classification(
        'Genus',
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
    ),
    [
      LocalPicture(
        Picture(id: 'pic1', species: id, origin: 'fishbase', isUsable: 1),
        '1.jpg',
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WatchlistService watchlistService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    watchlistService = WatchlistService(await SharedPreferences.getInstance());
  });

  Widget buildApp(SpeciesWithLocalImages species) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<WatchlistService>.value(value: watchlistService),
      ],
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FlashcardImageHeader(speciesWithLocalImages: species),
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
}
