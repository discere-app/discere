import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/catalog/species_detail/species_detail_page.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/navigation_tab_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSourceService implements SourceService {
  @override
  Future<List<Source>> getAllSources() async => const [];

  @override
  Future<List<({String key, String? licenseUrl})>> getDistinctLicenses() async {
    return const [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('species detail toggles watchlist membership', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final watchlistService = WatchlistService(prefs);
    final languageService = LanguageService(prefs);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WatchlistService>.value(
            value: watchlistService,
          ),
          ChangeNotifierProvider<LanguageService>.value(value: languageService),
          ChangeNotifierProvider<NavigationTabService>(
            create: (_) => NavigationTabService(),
          ),
          Provider<SourceService>.value(value: _FakeSourceService()),
        ],
        child: _buildApp(SpeciesDetailPage(species: _sampleSpecies())),
      ),
    );
    await tester.pump();

    final button = find.byKey(const Key('species_detail_watchlist_button'));
    expect(button, findsOneWidget);
    expect(watchlistService.containsSpecies('sp1'), isFalse);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

    await tester.tap(button);
    await tester.pump();

    expect(watchlistService.containsSpecies('sp1'), isTrue);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    await tester.tap(button);
    await tester.pump();

    expect(watchlistService.containsSpecies('sp1'), isFalse);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
  });
}

SpeciesWithLocalImages _sampleSpecies() {
  return SpeciesWithLocalImages(
    Species(
      'sp1',
      'sp1',
      'fishbase',
      'ocellaris',
      {
        Language.en: ['Clown anemonefish'],
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
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
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
