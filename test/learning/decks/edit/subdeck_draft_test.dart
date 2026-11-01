import 'package:discere/learning/decks/edit/subdeck_draft.dart';
import 'package:discere/learning/model/subdeck.dart';
import 'package:flutter_test/flutter_test.dart';

const _saved = SubdeckDraft(
  subdecks: [
    (id: 'l1', name: 'One'),
    (id: 'l2', name: 'Two'),
    (id: 'l3', name: 'Three'),
  ],
  subdeckIdBySpeciesId: {'sp-a': 'l1', 'sp-b': 'l2', 'unresolved': 'l1'},
  activeSubdeckIds: {'l1', 'l3'},
);

SubdeckDraft _edited(SubdeckDraft Function(SubdeckDraft) change) =>
    change(_saved);

void main() {
  test('takes over what is stored', () {
    final draft = SubdeckDraft.ofStored(
      const [
        Subdeck(deckId: 'd', id: 'l1', name: 'A', sortOrder: 0, isActive: true),
        Subdeck(
          deckId: 'd',
          id: 'l2',
          name: 'B',
          sortOrder: 1,
          isActive: false,
        ),
      ],
      const {'sp-a': 'l2'},
    );

    expect(draft.subdecks, [(id: 'l1', name: 'A'), (id: 'l2', name: 'B')]);
    expect(draft.subdeckIdBySpeciesId, {'sp-a': 'l2'});
    expect(draft.activeSubdeckIds, {'l1'});
  });

  group('operations', () {
    test('add puts a switched-on subdeck at the end', () {
      final draft = _saved.add(id: 'new', name: 'New');

      expect(draft.subdecks.last, (id: 'new', name: 'New'));
      expect(draft.subdecks, hasLength(4));
      expect(draft.activeSubdeckIds, {'l1', 'l3', 'new'});
    });

    test('rename changes the name alone', () {
      final draft = _saved.rename('l2', 'Second');

      expect(draft.subdecks.map((s) => s.name), ['One', 'Second', 'Three']);
      expect(draft.subdecks.map((s) => s.id), ['l1', 'l2', 'l3']);
    });

    test('remove takes its species into no subdeck and leaves the rest', () {
      final draft = _saved.remove('l1');

      expect(draft.subdecks.map((s) => s.id), ['l2', 'l3']);
      expect(draft.subdeckIdBySpeciesId, {'sp-b': 'l2'});
      expect(draft.activeSubdeckIds, {'l3'});
    });

    test('reorder moves a subdeck to the position it ends up at', () {
      List<String> order(SubdeckDraft draft) =>
          draft.subdecks.map((s) => s.id).toList();

      expect(order(_saved.reorder(0, 2)), ['l2', 'l3', 'l1']);
      expect(order(_saved.reorder(2, 0)), ['l3', 'l1', 'l2']);
      expect(order(_saved.reorder(0, 1)), ['l2', 'l1', 'l3']);
      expect(order(_saved.reorder(1, 1)), ['l1', 'l2', 'l3']);
    });

    test('move takes species into a subdeck from wherever they are', () {
      final draft = _saved.move({'sp-a', 'sp-b', 'sp-c'}, 'l3');

      expect(draft.subdeckIdBySpeciesId, {
        'sp-a': 'l3',
        'sp-b': 'l3',
        'sp-c': 'l3',
        'unresolved': 'l1',
      });
    });

    test('move to null takes species into no subdeck, the others stay', () {
      expect(_saved.move({'sp-a', 'sp-c'}, null).subdeckIdBySpeciesId, {
        'sp-b': 'l2',
        'unresolved': 'l1',
      });
    });

    test('removeSpecies forgets the subdecks of the species', () {
      expect(_saved.removeSpecies({'sp-a', 'sp-b'}).subdeckIdBySpeciesId, {
        'unresolved': 'l1',
      });
    });

    test('subdeckNameBySpeciesId follows the draft', () {
      expect(_saved.subdeckNameBySpeciesId(), {
        'sp-a': 'One',
        'sp-b': 'Two',
        'unresolved': 'One',
      });
      expect(
        _saved.rename('l2', 'Second').subdeckNameBySpeciesId()['sp-b'],
        'Second',
      );
      expect(
        _saved.remove('l2').subdeckNameBySpeciesId().containsKey('sp-b'),
        isFalse,
      );
    });

    test('withActive replaces the ones on', () {
      expect(_saved.withActive({'l2'}).activeSubdeckIds, {'l2'});
    });
  });

  group('isNameTaken', () {
    test('ignores case and surrounding space', () {
      expect(_saved.isNameTaken('  oNe '), isTrue);
      expect(_saved.isNameTaken('Four'), isFalse);
    });

    test('a subdeck does not stand in its own way', () {
      expect(_saved.isNameTaken('one', exceptSubdeckId: 'l1'), isFalse);
      expect(_saved.isNameTaken('two', exceptSubdeckId: 'l1'), isTrue);
    });
  });

  group('editSince', () {
    test('nothing changed is no edit', () {
      expect(_saved.editSince(_saved, removedSpeciesIds: const {}), isNull);
    });

    test('a switch alone is no edit', () {
      expect(
        _saved
            .withActive({'l2'})
            .editSince(_saved, removedSpeciesIds: const {}),
        isNull,
      );
    });

    test('a species leaving the deck is no edit', () {
      expect(
        _saved
            .removeSpecies({'sp-a'})
            .editSince(_saved, removedSpeciesIds: {'sp-a'}),
        isNull,
      );
    });

    test('changes turned back are no edit', () {
      for (final turnedBack in [
        _edited((d) => d.reorder(0, 2).reorder(2, 0)),
        _edited((d) => d.rename('l1', 'Other').rename('l1', 'One')),
        _edited((d) => d.add(id: 'new', name: 'New').remove('new')),
        _edited((d) => d.move({'sp-a'}, 'l2').move({'sp-a'}, 'l1')),
      ]) {
        expect(
          turnedBack.editSince(_saved, removedSpeciesIds: const {}),
          isNull,
        );
        expect(turnedBack.hasSameContentAs(_saved), isTrue);
      }
    });

    test('moves name the species that really change subdeck', () {
      final edit = _edited(
        (d) => d.move({'sp-a', 'sp-new'}, 'l3'),
      ).editSince(_saved, removedSpeciesIds: const {});

      expect(edit!.moves, {'sp-a': 'l3', 'sp-new': 'l3'});
      expect(edit.subdecks, _saved.subdecks);
    });

    test('a species taken out of its subdeck moves to none', () {
      final edit = _edited(
        (d) => d.move({'sp-b'}, null),
      ).editSince(_saved, removedSpeciesIds: const {});

      expect(edit!.moves, {'sp-b': null});
    });

    test('a removed and added-again species really left its subdeck', () {
      final edit = _saved
          .removeSpecies({'sp-a'})
          .editSince(_saved, removedSpeciesIds: const {});

      expect(edit!.moves, {'sp-a': null});
    });

    test('a new order is an edit without moves', () {
      final edit = _saved
          .reorder(0, 1)
          .editSince(_saved, removedSpeciesIds: const {});

      expect(edit!.subdecks.map((s) => s.id), ['l2', 'l1', 'l3']);
      expect(edit.moves, isEmpty);
    });
  });

  group('hasSameContentAs', () {
    test('tells every part apart', () {
      expect(_saved.hasSameContentAs(_saved.reorder(0, 1)), isFalse);
      expect(_saved.hasSameContentAs(_saved.rename('l1', 'X')), isFalse);
      expect(_saved.hasSameContentAs(_saved.removeSpecies({'sp-a'})), isFalse);
      expect(_saved.hasSameContentAs(_saved.withActive({'l1'})), isFalse);
    });

    test('the order of the switches does not matter', () {
      expect(_saved.hasSameContentAs(_saved.withActive({'l3', 'l1'})), isTrue);
    });
  });
}
