import 'dart:async';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/catalog/watchlist/watchlist_page.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

SpeciesWithLocalImages _buildItem(String id, String scientificName) {
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
      const [],
    ),
    const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'dismissed species stays removed while a slow reload is still resolving',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'watchlist': ['sp1', 'sp2'],
      });
      final prefs = await SharedPreferences.getInstance();
      final watchlistService = WatchlistService(prefs);
      final languageService = LanguageService(prefs);

      final reloadCompleter = Completer<List<SpeciesWithLocalImages>>();
      int callCount = 0;

      Future<List<SpeciesWithLocalImages>> resolveSpecies(
        Set<String> ids,
      ) async {
        callCount++;
        if (callCount == 1) {
          return [_buildItem('sp1', 'one'), _buildItem('sp2', 'two')];
        }
        // Second call happens after dismissing sp1 — kept pending on
        // purpose to exercise the reload-still-in-flight window.
        return reloadCompleter.future;
      }

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<WatchlistService>.value(
              value: watchlistService,
            ),
            ChangeNotifierProvider<LanguageService>.value(
              value: languageService,
            ),
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
              body: WatchlistPage(
                resolveSpecies: resolveSpecies,
                buildSpeciesDetailPage: (id) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Genus one'), findsWidgets);
      expect(find.textContaining('Genus two'), findsWidgets);

      // Swipe to dismiss "Genus one". This triggers a reload (via
      // WatchlistService.notifyListeners() -> hasChanged) that stays
      // pending on `reloadCompleter` for a few pumps below — regression
      // coverage for a bug where FutureBuilder's stale "waiting" snapshot
      // (which still carries the *previous* future's data) clobbered the
      // optimistic removal and re-added the dismissed item, crashing with
      // "A dismissed Dismissible widget is still part of the tree."
      await tester.fling(
        find.textContaining('Genus one').first,
        const Offset(-500, 0),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Genus one'), findsNothing);

      reloadCompleter.complete([_buildItem('sp2', 'two')]);
      await tester.pumpAndSettle();

      expect(find.textContaining('Genus one'), findsNothing);
      expect(find.textContaining('Genus two'), findsWidgets);
    },
  );
}
