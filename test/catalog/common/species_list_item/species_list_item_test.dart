import 'package:cached_network_image/cached_network_image.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_view_model.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../support/installed_package.dart';

void main() {
  testWidgets("loads a remote picture with the app's User-Agent", (
    tester,
  ) async {
    await tester.pumpWidget(
      Provider<PackageInfo>.value(
        value: installedPackage,
        child: const MaterialApp(
          home: Scaffold(
            body: SpeciesListItem(
              item: SpeciesListItemViewModel(
                primaryName: 'Red lionfish',
                scientificName: 'Pterois miles',
                additionalNames: null,
                localImagePath: null,
                remoteImageUrl: 'https://images.test/pterois.jpg',
                matchedSynonym: null,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .httpHeaders,
      {'User-Agent': AppConstants.userAgentFor(installedPackage.version)},
    );
  });

  group('generic slots', () {
    const item = SpeciesListItemViewModel(
      primaryName: 'Red lionfish',
      scientificName: 'Pterois miles',
      additionalNames: null,
      localImagePath: null,
      remoteImageUrl: null,
      matchedSynonym: null,
    );

    testWidgets('shows a footer under the names', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpeciesListItem(item: item, footer: Text('Reef')),
          ),
        ),
      );

      expect(
        tester.getTopLeft(find.text('Reef')).dy,
        greaterThan(tester.getBottomLeft(find.text('Pterois miles')).dy - 1),
      );
    });

    testWidgets('a long press is not a tap', (tester) async {
      var tapped = 0;
      var longPressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpeciesListItem(
              item: item,
              onTap: () => tapped++,
              onLongPress: () => longPressed++,
            ),
          ),
        ),
      );

      await tester.longPress(find.text('Red lionfish'));
      await tester.pumpAndSettle();
      expect((tapped, longPressed), (0, 1));

      await tester.tap(find.text('Red lionfish'));
      await tester.pumpAndSettle();
      expect((tapped, longPressed), (1, 1));
    });
  });

  group('matched synonym', () {
    SpeciesListItemViewModel item(String? matchedSynonym) =>
        SpeciesListItemViewModel(
          primaryName: 'Indian threadfish',
          scientificName: 'Scyris indica',
          additionalNames: null,
          localImagePath: null,
          remoteImageUrl: null,
          matchedSynonym: matchedSynonym,
        );

    Future<void> pump(WidgetTester tester, SpeciesListItemViewModel item) =>
        tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: SpeciesListItem(item: item)),
          ),
        );

    testWidgets('names the synonym a search found the species through, in '
        'italics', (tester) async {
      await pump(tester, item('Alectis indica'));

      final line = tester.widget<Text>(
        find.text('Former name: Alectis indica'),
      );
      final synonymSpan = (line.textSpan! as TextSpan).children!
          .cast<TextSpan>()
          .singleWhere((span) => span.text == 'Alectis indica');
      expect(synonymSpan.style?.fontStyle, FontStyle.italic);
    });

    testWidgets('is not shown for a species found directly', (tester) async {
      await pump(tester, item(null));

      expect(find.textContaining('Former name'), findsNothing);
    });
  });
}
