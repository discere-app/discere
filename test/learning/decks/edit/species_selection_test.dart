import 'package:discere/learning/decks/edit/species_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const all = {'a', 'b'};

  test('none is not selecting; empty is, with nothing selected', () {
    expect(SpeciesSelection.none.isActive, isFalse);
    expect(SpeciesSelection.empty.isActive, isTrue);
    expect(SpeciesSelection.empty.hasSelection, isFalse);
  });

  test('starting with a species selects it', () {
    final selection = SpeciesSelection.startingWith('a');

    expect(selection.isActive, isTrue);
    expect(selection.isSelected('a'), isTrue);
    expect(selection.isSelected('b'), isFalse);
  });

  test('toggling flips one, and deselecting the last stays active', () {
    final selection = SpeciesSelection.empty.toggled('a').toggled('b');
    expect(selection.selectedIds, all);

    final emptied = selection.toggled('a').toggled('b');
    expect(emptied.hasSelection, isFalse);
    expect(emptied.isActive, isTrue);
  });

  test('all selects everything, and again nothing', () {
    final partly = SpeciesSelection.startingWith('a');
    expect(partly.isAllSelected(all), isFalse);

    final everything = partly.toggledAll(all);
    expect(everything.selectedIds, all);
    expect(everything.isAllSelected(all), isTrue);

    final nothing = everything.toggledAll(all);
    expect(nothing.selectedIds, isEmpty);
    expect(nothing.isActive, isTrue);
  });

  test('an empty list is never all selected', () {
    expect(SpeciesSelection.empty.isAllSelected(const {}), isFalse);
  });
}
