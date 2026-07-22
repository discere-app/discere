import 'package:discere/catalog/model/region_abundance.dart';
import 'package:discere/catalog/taxonomy_detail/species_filter_sheet.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_species_selection_presenter.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows the reset button only once a filter is active, and reset clears it',
    (tester) async {
      await tester.pumpWidget(
        _buildApp(
          SpeciesFilterSheet(
            availableRegionKeys: const [],
            initiallySelectedRegionKeys: const {},
            initiallySelectedTiers:
                TaxonomySpeciesSelectionPresenter.allFrequencyTiers,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final resetButton = find.byKey(
        const Key('species_filter_sheet_reset_button'),
      );
      expect(resetButton, findsNothing);

      await tester.tap(find.text('Häufigkeit'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('species_filter_sheet_tier_scarce')),
      );
      await tester.pumpAndSettle();

      expect(resetButton, findsOneWidget);

      await tester.tap(resetButton);
      await tester.pumpAndSettle();

      expect(resetButton, findsNothing);
      final scarceCheckbox = tester.widget<CheckboxListTile>(
        find.byKey(const Key('species_filter_sheet_tier_scarce')),
      );
      expect(scarceCheckbox.value, isTrue);
    },
  );

  testWidgets('reset also clears a selected region', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        SpeciesFilterSheet(
          availableRegionKeys: const ['818'],
          initiallySelectedRegionKeys: const {'818'},
          initiallySelectedTiers: {RegionAbundance.abundant},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final resetButton = find.byKey(
      const Key('species_filter_sheet_reset_button'),
    );
    expect(resetButton, findsOneWidget);

    await tester.tap(resetButton);
    await tester.pumpAndSettle();

    expect(resetButton, findsNothing);
    final regionCheckbox = tester.widget<CheckboxListTile>(
      find.byKey(const Key('species_filter_sheet_region_818')),
    );
    expect(regionCheckbox.value, isFalse);
  });
}

Widget _buildApp(Widget child) {
  return MaterialApp(
    locale: const Locale('de'),
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}
