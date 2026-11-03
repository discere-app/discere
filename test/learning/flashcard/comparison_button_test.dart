import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/learning/flashcard/flashcard_back_content.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../catalog/comparison/comparison_test_app.dart';

final _cardSpecies = Species(
  'sp1',
  'ext1',
  'fishbase',
  'carcharias',
  const {
    Language.en: ['Great white shark'],
  },
  Classification(
    'Carcharodon',
    const {},
    null,
    'Lamnidae',
    const {},
    'Lamniformes',
    const {},
    'Chondrichthyes',
    const {},
    null,
  ),
  const [],
);

void main() {
  testWidgets('the button on the back of a card adds exactly the card\'s '
      'species to the comparison picked', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final watchlistService = WatchlistService(
      await SharedPreferences.getInstance(),
    );
    final service = await loadedComparisonListService(tester, const [
      ComparisonList(id: 'l1', name: 'Sharks', speciesIds: ['sp0']),
    ]);
    await tester.pumpWidget(
      comparisonTestApp(
        service: service,
        providers: [
          ChangeNotifierProvider<WatchlistService>.value(
            value: watchlistService,
          ),
        ],
        home: Scaffold(
          body: FlashcardBackContent(
            speciesWithLocalImages: SpeciesWithLocalImages(_cardSpecies, []),
            language: Language.en,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('flashcard_compare_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('comparison_sheet_list_l1')));
    await tester.pumpAndSettle();

    expect(service.listById('l1')!.speciesIds, ['sp0', 'sp1']);
  });
}
