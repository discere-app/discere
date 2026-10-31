import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/edit/subdeck_draft.dart';
import 'package:discere/learning/decks/edit/subdeck_species_page.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Species _species(String id) => Species(
  id,
  'Genus $id',
  'fishbase',
  id,
  const {},
  Classification(
    'Genus',
    const {},
    null,
    'Family',
    const {},
    'Order',
    const {},
    'Class',
    const {},
    null,
  ),
  const [],
);

void main() {
  const here = (id: 'here', name: 'Here');
  const draft = SubdeckDraft(
    subdecks: [here, (id: 'other', name: 'Other')],
    subdeckIdBySpeciesId: {'a': 'here', 'b': 'other'},
    activeSubdeckIds: {'here', 'other'},
  );

  /// Pushes the page and hands back what it popped with, once it did.
  Future<Set<String>? Function()> pumpPage(WidgetTester tester) async {
    Set<String>? popped;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<Set<String>>(
                MaterialPageRoute(
                  builder: (_) => SubdeckSpeciesPage(
                    subdeck: here,
                    draft: draft,
                    species: [_species('a'), _species('b'), _species('c')],
                    language: Language.en,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => popped;
  }

  CheckboxListTile tile(WidgetTester tester, String id) =>
      tester.widget<CheckboxListTile>(
        find.byKey(Key('edit_deck_subdeck_species_tile_$id')),
      );

  testWidgets('lists every species with the subdeck it is in, those of this '
      'subdeck checked', (tester) async {
    await pumpPage(tester);

    expect(tile(tester, 'a').value, isTrue);
    expect(tile(tester, 'b').value, isFalse);
    expect(tile(tester, 'c').value, isFalse);
    expect((tile(tester, 'a').subtitle! as Text).data, 'Here');
    expect((tile(tester, 'b').subtitle! as Text).data, 'Other');
    expect((tile(tester, 'c').subtitle! as Text).data, 'In no subdeck');
  });

  testWidgets('confirming pops with what is checked', (tester) async {
    final popped = await pumpPage(tester);

    await tester.tap(find.byKey(const Key('edit_deck_subdeck_species_tile_a')));
    await tester.tap(find.byKey(const Key('edit_deck_subdeck_species_tile_b')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('edit_deck_subdeck_species_confirm_button')),
    );
    await tester.pumpAndSettle();

    expect(popped(), {'b'});
  });

  testWidgets('going back pops with nothing', (tester) async {
    final popped = await pumpPage(tester);

    await tester.tap(find.byKey(const Key('edit_deck_subdeck_species_tile_b')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(popped(), isNull);
  });
}
