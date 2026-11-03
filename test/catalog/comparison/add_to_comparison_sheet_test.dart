import 'package:discere/catalog/comparison/add_to_comparison_sheet.dart';
import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/service/comparison_list_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'comparison_test_app.dart';
import 'fake_comparison_list_repository.dart';

/// Fails the first [addSpecies], as a write the database refuses would.
class _FailingOnceRepository extends FakeComparisonListRepository {
  _FailingOnceRepository(super.lists);

  bool _failed = false;

  @override
  Future<void> addSpecies(
    String listId,
    Set<String> speciesIds, {
    required DateTime at,
  }) async {
    if (!_failed) {
      _failed = true;
      throw StateError('disk full');
    }
    await super.addSpecies(listId, speciesIds, at: at);
  }
}

void main() {
  /// Mounts a page whose button opens the sheet for [speciesIds], and
  /// returns what the sheet resolved to once it has closed.
  Future<bool? Function()> pumpSheetOpener(
    WidgetTester tester,
    ComparisonListService service, {
    required Set<String> speciesIds,
    required Set<String> speciesNames,
  }) async {
    bool? result;
    await tester.pumpWidget(
      comparisonTestApp(
        service: service,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showAddToComparisonSheet(
                context,
                speciesIds: speciesIds,
                speciesNames: speciesNames,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  Finder listTile(String id) =>
      find.byKey(ValueKey('comparison_sheet_list_$id'));

  testWidgets('a list that already holds every species is checked and cannot '
      'be picked; picking another adds them and closes the sheet', (
    tester,
  ) async {
    final service = await loadedComparisonListService(tester, const [
      ComparisonList(id: 'complete', name: 'Has it', speciesIds: ['sp1']),
      ComparisonList(id: 'other', name: 'Rays', speciesIds: ['sp2']),
    ]);
    final result = await pumpSheetOpener(
      tester,
      service,
      speciesIds: {'sp1'},
      speciesNames: {'Dasyatis pastinaca'},
    );

    expect(
      find.descendant(
        of: listTile('complete'),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    await tester.tap(listTile('complete'));
    await tester.pumpAndSettle();
    expect(find.byType(AddToComparisonSheet), findsOneWidget);
    expect(result(), isNull);

    await tester.tap(listTile('other'));
    await tester.pumpAndSettle();

    expect(find.byType(AddToComparisonSheet), findsNothing);
    expect(result(), isTrue);
    expect(service.listById('other')!.speciesIds, ['sp2', 'sp1']);
    expect(service.listById('complete')!.speciesIds, ['sp1']);
    expect(find.text('Added 1 species to "Rays"'), findsOneWidget);
  });

  testWidgets('"New comparison" suggests a name from the species and creates '
      'the list with them', (tester) async {
    final service = await loadedComparisonListService(tester);
    final result = await pumpSheetOpener(
      tester,
      service,
      speciesIds: {'sp1', 'sp2'},
      speciesNames: {'Dasyatis pastinaca', 'Taeniura lymma'},
    );
    expect(find.text('No comparisons yet. Create a new one.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('comparison_sheet_create_new')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('comparison_name_field')))
          .controller!
          .text,
      'Dasyatis pastinaca, Taeniura lymma',
    );
    await tester.tap(find.byKey(const Key('comparison_name_confirm_button')));
    await tester.pumpAndSettle();

    expect(result(), isTrue);
    final created = service.lists!.single;
    expect(created.name, 'Dasyatis pastinaca, Taeniura lymma');
    expect(created.speciesIds, ['sp1', 'sp2']);
  });

  testWidgets('closing the sheet adds nothing', (tester) async {
    final service = await loadedComparisonListService(tester, const [
      ComparisonList(id: 'l1', name: 'Rays', speciesIds: []),
    ]);
    final result = await pumpSheetOpener(
      tester,
      service,
      speciesIds: {'sp1'},
      speciesNames: {'Dasyatis pastinaca'},
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(result(), isFalse);
    expect(service.listById('l1')!.speciesIds, isEmpty);
  });

  testWidgets('a failed write is reported in the sheet, which stays open '
      'and can be used again', (tester) async {
    final service = ComparisonListService(
      _FailingOnceRepository(const [
        ComparisonList(id: 'l1', name: 'Rays', speciesIds: []),
      ]),
    );
    await tester.pump();
    final result = await pumpSheetOpener(
      tester,
      service,
      speciesIds: {'sp1'},
      speciesNames: {'Dasyatis pastinaca'},
    );

    await tester.tap(listTile('l1'));
    await tester.pumpAndSettle();

    expect(find.byType(AddToComparisonSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AddToComparisonSheet),
        matching: find.text(
          'Could not save the comparison: Something went wrong.',
        ),
      ),
      findsOneWidget,
    );
    expect(service.listById('l1')!.speciesIds, isEmpty);
    expect(result(), isNull);

    await tester.tap(listTile('l1'));
    await tester.pumpAndSettle();

    expect(find.byType(AddToComparisonSheet), findsNothing);
    expect(result(), isTrue);
    expect(service.listById('l1')!.speciesIds, ['sp1']);
  });
}
