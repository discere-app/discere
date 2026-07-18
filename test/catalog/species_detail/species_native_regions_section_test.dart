import 'package:discere/catalog/species_detail/species_native_region_view_model.dart';
import 'package:discere/catalog/species_detail/species_native_regions_section_view_model.dart';
import 'package:discere/catalog/species_detail/widgets/species_native_regions_section.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('localizes collapsed region controls', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        const SpeciesNativeRegionsSection(
          section: SpeciesNativeRegionsSectionViewModel(
            title: 'Regionen & Lebensräume',
            habitatTags: [],
            nativeRegions: [
              SpeciesNativeRegionViewModel(label: 'Region 1', subregions: []),
              SpeciesNativeRegionViewModel(label: 'Region 2', subregions: []),
              SpeciesNativeRegionViewModel(label: 'Region 3', subregions: []),
              SpeciesNativeRegionViewModel(label: 'Region 4', subregions: []),
              SpeciesNativeRegionViewModel(label: 'Region 5', subregions: []),
              SpeciesNativeRegionViewModel(label: 'Region 6', subregions: []),
              SpeciesNativeRegionViewModel(label: 'Region 7', subregions: []),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('+ 2 weitere Regionen'), findsOneWidget);
    expect(find.text('Region 6'), findsNothing);

    await tester.tap(find.text('+ 2 weitere Regionen'));
    await tester.pumpAndSettle();

    expect(find.text('Region 6'), findsOneWidget);
    expect(find.text('Weniger anzeigen'), findsOneWidget);
  });

  testWidgets(
    'shows an endemic badge next to the title when any region is endemic',
    (tester) async {
      await tester.pumpWidget(
        _buildApp(
          const SpeciesNativeRegionsSection(
            section: SpeciesNativeRegionsSectionViewModel(
              title: 'Regionen & Lebensräume',
              habitatTags: [],
              nativeRegions: [
                SpeciesNativeRegionViewModel(
                  label: 'Galápagos-Inseln',
                  isEndemic: true,
                ),
                SpeciesNativeRegionViewModel(label: 'Ecuador'),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Galápagos-Inseln'), findsOneWidget);
      expect(find.text('Ecuador'), findsOneWidget);
      expect(find.text('Endemisch'), findsOneWidget);
    },
  );

  testWidgets('shows no endemic badge when no region is endemic', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildApp(
        const SpeciesNativeRegionsSection(
          section: SpeciesNativeRegionsSectionViewModel(
            title: 'Regionen & Lebensräume',
            habitatTags: [],
            nativeRegions: [SpeciesNativeRegionViewModel(label: 'Ecuador')],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Endemisch'), findsNothing);
  });

  testWidgets(
    'shows a continent summary and hides the country list by default when widespread',
    (tester) async {
      await tester.pumpWidget(
        _buildApp(
          const SpeciesNativeRegionsSection(
            section: SpeciesNativeRegionsSectionViewModel(
              title: 'Regionen & Lebensräume',
              habitatTags: [],
              continents: ['Europa', 'Asien'],
              nativeRegions: [
                SpeciesNativeRegionViewModel(label: 'Country 1'),
                SpeciesNativeRegionViewModel(label: 'Country 2'),
                SpeciesNativeRegionViewModel(label: 'Country 3'),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Europa, Asien'), findsOneWidget);
      expect(find.text('Country 1'), findsNothing);
      expect(find.text('+ 3 weitere Regionen'), findsOneWidget);

      await tester.tap(find.text('+ 3 weitere Regionen'));
      await tester.pumpAndSettle();

      expect(find.text('Country 1'), findsOneWidget);
    },
  );
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
