import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/catalog/watchlist/watchlist_tab.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared setup for the WatchlistTab widget tests.

/// A watchlist entry. [localPath] non-null means its image is already on disk,
/// which is the only thing the two load passes differ in.
SpeciesWithLocalImages watchlistItem(
  String id,
  String scientificName, {
  String? localPath,
}) {
  final picture = Picture(
    id: 'pic-$id',
    species: id,
    origin: 'fishbase',
    isUsable: 1,
  );
  return SpeciesWithLocalImages(
    Species(
      id,
      id,
      'fishbase',
      scientificName,
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
      [picture],
    ),
    localPath == null ? const [] : [LocalPicture(picture, localPath)],
  );
}

/// Mounts [WatchlistTab] over a watchlist seeded with [watchlist], and returns
/// the service so a test can change the list from the outside.
Future<WatchlistService> pumpWatchlistTab(
  WidgetTester tester, {
  required List<String> watchlist,
  required ResolveWatchlistSpecies resolveFromCache,
  required ResolveWatchlistSpecies resolveWithDownload,
}) async {
  SharedPreferences.setMockInitialValues({'watchlist': watchlist});
  final prefs = await SharedPreferences.getInstance();
  final watchlistService = WatchlistService(prefs);
  final languageService = LanguageService(prefs);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WatchlistService>.value(value: watchlistService),
        ChangeNotifierProvider<LanguageService>.value(value: languageService),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: WatchlistTab(
            resolveFromCache: resolveFromCache,
            resolveWithDownload: resolveWithDownload,
            buildSpeciesDetailPage: (id) => const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
  return watchlistService;
}
