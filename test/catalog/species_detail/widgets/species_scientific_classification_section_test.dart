import 'package:discere/catalog/common/taxon_classification/classification_row_view_model.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/species_detail/widgets/species_scientific_classification_section.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kynaria cynara's chain: SeaLifeBase files it under the family "Not
/// assigned" of the order Nudibranchia.
const _rows = [
  ClassificationRowViewModel(
    type: ClassificationRowType.genus,
    id: 'discere:genus:1',
    scientificName: 'Kynaria',
  ),
  ClassificationRowViewModel(
    type: ClassificationRowType.family,
    id: 'discere:family:5210',
    scientificName: 'Not assigned',
    isUnassigned: true,
  ),
  ClassificationRowViewModel(
    type: ClassificationRowType.order,
    id: 'discere:order:362',
    scientificName: 'Nudibranchia',
  ),
];

void main() {
  for (final (locale, unassigned) in [
    (const Locale('de'), 'nicht zugeordnet'),
    (const Locale('en'), 'unassigned'),
  ]) {
    testWidgets('a placeholder rank reads "$unassigned" in $locale, '
        'not under the source\'s name', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          locale,
          SpeciesScientificClassificationSection(
            rows: _rows,
            onNavigate: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(unassigned), findsOneWidget);
      expect(find.text('Not assigned'), findsNothing);
      expect(find.text('Nudibranchia'), findsOneWidget);
    });
  }

  testWidgets('a placeholder rank opens its own page, flagged', (
    tester,
  ) async {
    final navigated = <SearchResult>[];
    await tester.pumpWidget(
      _buildApp(
        const Locale('de'),
        SpeciesScientificClassificationSection(
          rows: _rows,
          onNavigate: navigated.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('nicht zugeordnet'));
    await tester.pumpAndSettle();

    expect(navigated.single.id, 'discere:family:5210');
    expect(navigated.single.type, SearchEntityType.family);
    expect(navigated.single.isPlaceholder, isTrue);
  });
  testWidgets('a rank the chain does not reach reads "nicht zugeordnet" and '
      'leads nowhere', (tester) async {
    final navigated = <SearchResult>[];
    await tester.pumpWidget(
      _buildApp(
        const Locale('de'),
        SpeciesScientificClassificationSection(
          rows: const [
            ClassificationRowViewModel(
              type: ClassificationRowType.genus,
              id: 'discere:genus:5106',
              scientificName: 'Amphiprion',
            ),
            ClassificationRowViewModel(
              type: ClassificationRowType.family,
              scientificName: null,
              isUnassigned: true,
            ),
          ],
          onNavigate: navigated.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Familie'), findsOneWidget);
    expect(find.text('nicht zugeordnet'), findsOneWidget);
    await tester.tap(find.text('nicht zugeordnet'));
    await tester.pumpAndSettle();
    expect(navigated, isEmpty);
  });
}

Widget _buildApp(Locale locale, Widget child) {
  return MaterialApp(
    locale: locale,
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}
