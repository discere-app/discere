import 'package:discere/catalog/common/species_selection.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/decks/edit/species_selection_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../catalog/comparison/comparison_test_app.dart';

Species _species(String id, String epithet) => Species(
  id,
  id,
  'fishbase',
  epithet,
  const {},
  Classification(
    'Chromis',
    const {},
    null,
    'Pomacentridae',
    const {},
    'Ovalentaria',
    const {},
    'Actinopterygii',
    const {},
    null,
  ),
  const [],
);

void main() {
  testWidgets('adds the selected species to a new comparison, named after '
      'them, and ends the selection', (tester) async {
    final service = await loadedComparisonListService(tester);
    SpeciesSelection? changedTo;
    await tester.pumpWidget(
      comparisonTestApp(
        service: service,
        home: Scaffold(
          appBar: SpeciesSelectionAppBar(
            selection: SpeciesSelection.startingWith('sp2'),
            species: [
              _species('sp1', 'viridis'),
              _species('sp2', 'atripectoralis'),
            ],
            onChanged: (selection) => changedTo = selection,
            onDelete: () {},
            onAssignSubdeck: () {},
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('edit_deck_selection_compare_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comparison_sheet_create_new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comparison_name_confirm_button')));
    await tester.pumpAndSettle();

    final created = service.lists!.single;
    expect(created.speciesIds, ['sp2']);
    expect(created.name, 'Chromis atripectoralis');
    expect(changedTo?.isActive, isFalse);
  });
}
