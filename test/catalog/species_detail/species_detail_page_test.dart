import 'package:discere/catalog/common/taxon_identity/identity_header.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/catalog/species_detail/species_detail_page.dart';
import 'package:discere/catalog/species_detail/widgets/species_common_names_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_scientific_classification_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_summary_section.dart';
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

const _germanAndEnglishNames = {
  Language.de: ['Weißer Hai', 'Menschenhai'],
  Language.en: ['Great white shark', 'White pointer'],
};

SpeciesWithLocalImages _species({
  Map<Language, List<String>> commonNames = _germanAndEnglishNames,
  List<Picture> pictures = const [],
}) {
  return SpeciesWithLocalImages(
    Species(
      'sp1',
      'sp1',
      'fishbase',
      'carcharias',
      commonNames,
      Classification(
        'Carcharodon',
        const {},
        null,
        'Lamnidae',
        const {
          Language.de: ['Makrelenhaie'],
          Language.en: ['Mackerel sharks'],
        },
        'Lamniformes',
        const {},
        'Chondrichthyes',
        const {},
        null,
      ),
      pictures,
    ),
    const [],
  );
}

Finder _inHeader(String text) =>
    find.descendant(of: find.byType(IdentityHeader), matching: find.text(text));

Finder _inCommonNames(String text) => find.descendant(
  of: find.byType(SpeciesCommonNamesSection),
  matching: find.text(text),
);

Finder _inClassification(String text) => find.descendant(
  of: find.byType(SpeciesScientificClassificationSection),
  matching: find.text(text),
);

Future<void> _pickLanguage(
  WidgetTester tester, {
  required String chip,
  required String menuEntry,
}) async {
  await tester.tap(find.text(chip));
  await tester.pumpAndSettle();
  await tester.tap(find.text(menuEntry));
  await tester.pumpAndSettle();
}

void main() {
  late LanguageService languageService;
  late WatchlistService watchlistService;

  /// The app language in the settings is German (see [setUp]); the UI
  /// locale is English throughout, so menu entries read the same whichever
  /// language the names are in.
  Future<void> pumpPage(
    WidgetTester tester, {
    required SpeciesWithLocalImages species,
    Language? language,
    bool isRefreshingImages = false,
  }) {
    return tester.pumpWidget(
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
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: SpeciesDetailPage(
            species: species,
            language: language,
            isRefreshingImages: isRefreshingImages,
          ),
        ),
      ),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      LanguageService.sharedPreferencesLanguageKey: Language.de.value,
    });
    final prefs = await SharedPreferences.getInstance();
    languageService = LanguageService(prefs);
    watchlistService = WatchlistService(prefs);
  });

  testWidgets('picking a language in the header switches the primary name, '
      'the common-name list and the classification names', (tester) async {
    await pumpPage(tester, species: _species());
    await tester.pump();

    expect(_inHeader('Weißer Hai'), findsWidgets);
    expect(_inCommonNames('Menschenhai'), findsWidgets);
    expect(_inClassification('Makrelenhaie'), findsWidgets);

    await _pickLanguage(tester, chip: 'DE', menuEntry: 'English');

    expect(find.text('EN'), findsOneWidget);
    expect(_inHeader('Great white shark'), findsWidgets);
    expect(_inHeader('Weißer Hai'), findsNothing);
    expect(_inCommonNames('White pointer'), findsWidgets);
    expect(_inCommonNames('Menschenhai'), findsNothing);
    expect(_inClassification('Mackerel sharks'), findsWidgets);
    expect(_inClassification('Makrelenhaie'), findsNothing);
  });

  testWidgets('picking a language for the names leaves the language of the '
      'Wikipedia summary where it was', (tester) async {
    await pumpPage(tester, species: _species());
    await tester.pump();

    SpeciesSummarySection summarySection() =>
        tester.widget(find.byType(SpeciesSummarySection));

    expect(summarySection().language, Language.de);

    await _pickLanguage(tester, chip: 'DE', menuEntry: 'English');

    expect(_inHeader('Great white shark'), findsWidgets);
    expect(summarySection().language, Language.de);
  });

  testWidgets('starts in the language handed to the page rather than the '
      'app language, for the names and the summary alike', (tester) async {
    await pumpPage(tester, species: _species(), language: Language.en);
    await tester.pump();

    expect(find.text('EN'), findsOneWidget);
    expect(_inHeader('Great white shark'), findsWidgets);
    expect(
      tester
          .widget<SpeciesSummarySection>(find.byType(SpeciesSummarySection))
          .language,
      Language.en,
    );
  });

  testWidgets('marks the primary name as an English fallback exactly while '
      'the names are shown in a language the species has none in', (
    tester,
  ) async {
    await pumpPage(
      tester,
      species: _species(
        commonNames: const {
          Language.en: ['Great white shark'],
          Language.fr: ['Grand requin blanc'],
        },
      ),
    );
    await tester.pump();

    expect(_inHeader('Great white shark'), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(IdentityHeader),
        matching: find.byIcon(Icons.info_outline),
      ),
      findsOneWidget,
    );

    await _pickLanguage(tester, chip: 'DE', menuEntry: 'French');

    expect(_inHeader('Grand requin blanc'), findsWidgets);
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets('keeps the picked language when the page is rebuilt with '
      'newly loaded image data', (tester) async {
    await pumpPage(tester, species: _species());
    await tester.pump();

    await _pickLanguage(tester, chip: 'DE', menuEntry: 'English');

    await pumpPage(tester, species: _species(), isRefreshingImages: true);
    await tester.pump();
    await pumpPage(
      tester,
      species: _species(
        pictures: const [
          Picture(id: 'p1', species: 'sp1', origin: 'inat', isUsable: 1),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EN'), findsOneWidget);
    expect(_inHeader('Great white shark'), findsWidgets);
    expect(_inHeader('Weißer Hai'), findsNothing);
  });

  testWidgets('follows a change of the app language as long as no language '
      'was picked, and stays with the pick afterwards', (tester) async {
    await pumpPage(tester, species: _species());
    await tester.pump();

    expect(_inHeader('Weißer Hai'), findsWidgets);

    languageService.setLanguage(Language.en.value);
    await tester.pumpAndSettle();

    expect(find.text('EN'), findsOneWidget);
    expect(_inHeader('Great white shark'), findsWidgets);

    await _pickLanguage(tester, chip: 'EN', menuEntry: 'German');
    languageService.setLanguage(Language.fr.value);
    await tester.pumpAndSettle();

    expect(find.text('DE'), findsOneWidget);
    expect(_inHeader('Weißer Hai'), findsWidgets);
  });
}
