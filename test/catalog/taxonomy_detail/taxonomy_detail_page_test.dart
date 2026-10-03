import 'package:discere/catalog/common/taxon_identity/display_language_selector.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/search/search_result_card.dart';
import 'package:discere/catalog/taxonomy_detail/service/taxonomy_service.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_page.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_children_section.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_classification_section.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_common_names_card.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_hero_header.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _family = SearchResult(
  id: 'family-1',
  name: 'Lamnidae',
  commonNames: const {},
  type: SearchEntityType.family,
);

class _FakeTaxonomyService extends Fake implements TaxonomyService {
  @override
  Future<TaxonomyDetail> getDetail(SearchResult result) async {
    return TaxonomyDetail(
      result: result,
      commonNames: const {
        Language.de: ['Makrelenhaie', 'Heringshaie'],
        Language.en: ['Mackerel sharks', 'Porbeagles'],
      },
      classification: const [
        TaxonomyClassificationEntry(
          label: TaxonomyRankLabel.order,
          id: 'order-1',
          scientificName: 'Lamniformes',
          commonNames: {
            Language.de: ['Makrelenhaiartige'],
            Language.en: ['Lamniform sharks'],
          },
        ),
      ],
      metrics: const [],
      isReferenceBacked: true,
    );
  }

  @override
  Future<List<SearchResult>> getChildren(SearchResult parent) async {
    return [
      SearchResult(
        id: 'genus-1',
        name: 'Carcharodon',
        commonNames: const {
          Language.de: ['Weißhaie'],
          Language.en: ['Great whites'],
        },
        type: SearchEntityType.genus,
      ),
    ];
  }
}

Finder _inHeader(String text) => find.descendant(
  of: find.byType(TaxonomyHeroHeader),
  matching: find.text(text),
);

Finder _inCommonNames(String text) => find.descendant(
  of: find.byType(TaxonomyCommonNamesCard),
  matching: find.text(text),
);

Finder _inClassification(String text) => find.descendant(
  of: find.byType(TaxonomyClassificationSection),
  matching: find.text(text),
);

Finder _inChildren(String text) => find.descendant(
  of: find.byType(TaxonomyChildrenSection),
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

  /// The app language in the settings is German (see [setUp]); the UI
  /// locale is English throughout, so menu entries read the same whichever
  /// language the names are in.
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<TaxonomyService>.value(value: _FakeTaxonomyService()),
          ChangeNotifierProvider<LanguageService>.value(value: languageService),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: TaxonomyDetailPage(searchResult: _family),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      LanguageService.sharedPreferencesLanguageKey: Language.de.value,
    });
    languageService = LanguageService(await SharedPreferences.getInstance());
  });

  testWidgets('picking a language in the header switches the primary title, '
      'the common names, the classification rows and the child list', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(_inHeader('Makrelenhaie'), findsWidgets);
    expect(_inCommonNames('Heringshaie'), findsWidgets);
    expect(_inClassification('Makrelenhaiartige'), findsWidgets);
    expect(_inChildren('Weißhaie'), findsWidgets);

    await _pickLanguage(tester, chip: 'DE', menuEntry: 'English');

    expect(find.text('EN'), findsOneWidget);
    expect(_inHeader('Mackerel sharks'), findsWidgets);
    expect(_inHeader('Makrelenhaie'), findsNothing);
    expect(_inCommonNames('Porbeagles'), findsWidgets);
    expect(_inCommonNames('Heringshaie'), findsNothing);
    expect(_inClassification('Lamniform sharks'), findsWidgets);
    expect(_inClassification('Makrelenhaiartige'), findsNothing);
    expect(_inChildren('Great whites'), findsWidgets);
    expect(_inChildren('Weißhaie'), findsNothing);
  });

  testWidgets('shows the selector in the header\'s top-left corner, with the '
      'rank badge next to it', (tester) async {
    await pumpPage(tester);

    final header = find.byType(TaxonomyHeroHeader);
    final selector = tester.getRect(
      find.descendant(
        of: header,
        matching: find.byType(DisplayLanguageSelector),
      ),
    );
    final badge = tester.getRect(
      find.descendant(of: header, matching: find.byType(SearchEntityTypeBadge)),
    );

    // Flush with the header's inner left edge — its padding plus the
    // one-pixel border.
    expect(selector.left, tester.getRect(header).left + AppSpacing.s20 + 1);
    expect(badge.left, selector.right + AppSpacing.s8);
    expect(badge.center.dy, moreOrLessEquals(selector.center.dy));
  });

  testWidgets('offers only the languages the taxon has a common name in', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('DE'));
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuItem<Language>), findsNWidgets(2));
    expect(
      find.widgetWithText(PopupMenuItem<Language>, 'German'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(PopupMenuItem<Language>, 'English'),
      findsOneWidget,
    );
  });

  testWidgets('follows a change of the app language as long as no language '
      'was picked, and stays with the pick afterwards', (tester) async {
    await pumpPage(tester);

    expect(_inHeader('Makrelenhaie'), findsWidgets);

    languageService.setLanguage(Language.en.value);
    await tester.pumpAndSettle();

    expect(find.text('EN'), findsOneWidget);
    expect(_inHeader('Mackerel sharks'), findsWidgets);

    await _pickLanguage(tester, chip: 'EN', menuEntry: 'German');
    languageService.setLanguage(Language.fr.value);
    await tester.pumpAndSettle();

    expect(find.text('DE'), findsOneWidget);
    expect(_inHeader('Makrelenhaie'), findsWidgets);
  });
}
