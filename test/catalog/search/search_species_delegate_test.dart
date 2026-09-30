import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_online_button.dart';
import 'package:discere/catalog/search/search_result_thumbnail.dart';
import 'package:discere/catalog/search/search_species_delegate.dart';
import 'package:discere/catalog/service/species_search_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the two states the search screen used to show something other
/// than what was actually true: a query too short to search at all, and a
/// round that failed while results were already on screen.
void main() {
  // The thumbnail cache is static and shared across every test in this
  // shard, so a name resolved here must not leak into the next test.
  setUp(SearchResultThumbnail.resetCacheForTesting);

  final octopus = SearchResult(
    id: 'species-1',
    name: 'Enteroctopus dofleini',
    commonNames: const {
      Language.en: ['Giant Pacific octopus'],
    },
    type: SearchEntityType.species,
  );

  testWidgets('a query too short to search asks for more input rather than '
      'showing a spinner that answers nothing', (tester) async {
    await _openSearch(tester, _StubSearchService());

    await tester.enterText(find.byType(EditableText), 'a');
    await tester.pumpAndSettle();

    expect(find.text('Start with the search input'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('drops back to the hint when the query is shortened below the '
      'minimum again', (tester) async {
    await _openSearch(tester, _StubSearchService(quick: [octopus]));

    await tester.enterText(find.byType(EditableText), 'octo');
    await tester.pumpAndSettle();
    expect(find.text('Giant Pacific octopus'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'o');
    await tester.pumpAndSettle();

    expect(find.text('Start with the search input'), findsOneWidget);
    expect(find.text('Giant Pacific octopus'), findsNothing);
  });

  testWidgets('says that the search failed while its results are still on '
      'screen', (tester) async {
    await _openSearch(
      tester,
      _StubSearchService(
        quick: [octopus],
        fullError: NetworkException('offline'),
      ),
    );

    await tester.enterText(find.byType(EditableText), 'octo');
    await tester.pumpAndSettle();

    expect(find.text('Giant Pacific octopus'), findsOneWidget);
    expect(
      find.text('The search ran into a problem: No internet connection.'),
      findsOneWidget,
    );
    expect(find.byType(SearchOnlineButton), findsOneWidget);
  });

  testWidgets('stays quiet about failures when there were none', (
    tester,
  ) async {
    await _openSearch(tester, _StubSearchService(quick: [octopus]));

    await tester.enterText(find.byType(EditableText), 'octo');
    await tester.pumpAndSettle();

    expect(find.textContaining('ran into a problem'), findsNothing);
  });
}

class _StubSearchService extends Fake implements SpeciesSearchService {
  _StubSearchService({this.quick = const [], this.fullError});

  final List<SearchResult> quick;
  final Object? fullError;

  @override
  Future<List<SearchResult>> searchQuick(String term) async => quick;

  @override
  Future<List<SearchResult>> searchAll(String term) async {
    if (fullError != null) throw fullError!;
    return const [];
  }

  @override
  void cancelCurrentSearch() {}
}

class _StubLanguageService extends Fake implements LanguageService {
  @override
  Language getLanguage() => Language.en;
}

/// Opens the delegate the way the app does — through `showSearch`, so the
/// query flows in from the real search field rather than being set by hand.
Future<void> _openSearch(
  WidgetTester tester,
  SpeciesSearchService searchService,
) async {
  final delegate = SearchSpeciesDelegate(
    searchService,
    _StubLanguageService(),
    (_) async => const [],
    (_) async => null,
    (_) => const SizedBox.shrink(),
  );

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSearch<String>(
                context: context,
                delegate: delegate,
              ),
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open search'));
  await tester.pumpAndSettle();
}
