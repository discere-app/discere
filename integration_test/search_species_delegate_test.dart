import 'dart:async';

import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/model/language.dart';
import 'package:discere/model/search/search_result.dart';
import 'package:discere/persistence/search_repository.dart';
import 'package:discere/service/common/language_service.dart';
import 'package:discere/ui/search_species_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSearchRepository extends SearchRepository {
  final List<String> quickQueries = [];
  final List<String> fullQueries = [];

  _FakeSearchRepository();

  @override
  Future<List<SearchResult>> searchQuick(String term) async {
    quickQueries.add(term);
    return [
      SearchResult(
        id: 'genus-1',
        name: 'Enteroctopus',
        commonNames: const {
          Language.en: 'Giant Pacific octopus',
          Language.de: 'Riesenpazifischer Krake',
        },
        type: SearchEntityType.genus,
      ),
    ];
  }

  @override
  Future<List<SearchResult>> searchAll(String term) async {
    fullQueries.add(term);
    return [
      SearchResult(
        id: 'genus-1',
        name: 'Enteroctopus',
        commonNames: const {
          Language.en: 'Giant Pacific octopus',
          Language.de: 'Riesenpazifischer Krake',
        },
        type: SearchEntityType.genus,
      ),
      SearchResult(
        id: 'family-1',
        name: 'Octopodidae',
        commonNames: const {Language.en: 'Octopuses', Language.de: 'Kraken'},
        type: SearchEntityType.family,
      ),
    ];
  }
}

class _FakeINaturalistService extends INaturalistService {
  @override
  Future<String?> fetchThumbnailUrl(
    String scientificName, {
    int? taxonId,
  }) async => null;

  @override
  Future<List<Map<String, dynamic>>> searchTaxa(
    String query, {
    int perPage = 20,
  }) async => const [];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSearchApp(
    WidgetTester tester, {
    required SearchSpeciesDelegate delegate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    unawaited(
                      showSearch<String>(context: context, delegate: delegate),
                    );
                  },
                  child: const Text('Open Search'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'quick search is debounced and only the final fast-typed query runs',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = _FakeSearchRepository();
      final delegate = SearchSpeciesDelegate(
        repo,
        LanguageService(prefs),
        _FakeINaturalistService(),
      );

      await pumpSearchApp(tester, delegate: delegate);
      await tester.tap(find.text('Open Search'));
      await tester.pumpAndSettle();

      final input = find.byType(EditableText);
      expect(input, findsOneWidget);

      const steps = <String>[
        'g',
        'gi',
        'gia',
        'gian',
        'giant',
        'giant ',
        'giant p',
        'giant pa',
        'giant pac',
        'giant paci',
        'giant pacif',
        'giant pacifi',
        'giant pacific',
        'giant pacific ',
        'giant pacific o',
        'giant pacific oc',
        'giant pacific oct',
        'giant pacific octo',
        'giant pacific octop',
        'giant pacific octopu',
        'giant pacific octopus',
      ];

      for (final value in steps) {
        await tester.enterText(input, value);
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(repo.quickQueries, isEmpty);
      expect(repo.fullQueries, isEmpty);

      await tester.pump(const Duration(milliseconds: 200));
      expect(repo.quickQueries, isEmpty);

      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(repo.quickQueries, ['giant pacific octopus']);
      expect(find.text('Giant Pacific octopus'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 360));
      await tester.pump();

      expect(repo.fullQueries, ['giant pacific octopus']);
      expect(find.text('Octopuses'), findsOneWidget);
    },
  );
}
