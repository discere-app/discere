import 'package:discere/learning/model/create_deck.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/learning_test_stack.dart';

/// A deck with subdecks imported from its JSON and shared again, against
/// real databases.
const _deckJson = '''
{
  "name": "Sharks",
  "description": "",
  "speciesNames": ["Carcharodon carcharias", "Prionace glauca",
                   "Rhincodon typus", "Zzz unknownus"],
  "subdecks": [
    {"id": "l1", "name": "Level 1",
     "speciesNames": ["Carcharodon carcharias"]},
    {"id": "l2", "name": "Level 2",
     "speciesNames": ["Prionace glauca", "Zzz unknownus"]}
  ]
}
''';

const _greatWhite = 'discere:species:694';
const _blueShark = 'discere:species:834';
const _whaleShark = 'discere:species:1872';
const _tigerShark = 'discere:species:822';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LearningTestStack stack;
  late String deckId;

  setUp(() async {
    stack = await LearningTestStack.open();
    final result = await stack.importService.importDecks([
      CreateDeck.fromJsonString(_deckJson),
    ]);
    deckId = result.importedDeckIds.single;
  });

  tearDown(() => stack.close());

  test('imports one deck, every subdeck active, each species in its own and '
      'the rest in none', () async {
    expect(await stack.stats.getSpeciesIdsByDeckId(deckId), {
      _greatWhite,
      _blueShark,
      _whaleShark,
    });
    final subdecks = await stack.decksService.getSubdecks(deckId);
    expect(subdecks.map((s) => (s.id, s.name, s.isActive, s.speciesCount)), [
      ('l1', 'Level 1', true, 1),
      ('l2', 'Level 2', true, 1),
    ]);
    expect(await stack.subdecks.getSubdeckIdBySpeciesId(deckId), {
      _greatWhite: 'l1',
      _blueShark: 'l2',
    });
  });

  test('a name resolved later lands in the subdeck it was listed in', () async {
    await stack.decksService.addResolvedSpeciesToDeck(
      deckId,
      _tigerShark,
      resolvedName: 'Zzz unknownus',
    );

    expect(
      await stack.stats.getSpeciesIdsByDeckId(deckId),
      contains(_tigerShark),
    );
    expect(
      (await stack.subdecks.getSubdeckIdBySpeciesId(deckId))[_tigerShark],
      'l2',
    );
  });

  test('a species added by hand belongs to no subdeck', () async {
    await stack.decksService.addSpeciesToDeck(deckId, {_tigerShark});

    expect(
      (await stack.subdecks.getSubdeckIdBySpeciesId(
        deckId,
      )).containsKey(_tigerShark),
      isFalse,
    );
  });

  test('a removed species leaves its subdeck', () async {
    await stack.decksService.removeSpeciesFromDeck(deckId, _blueShark);

    expect((await stack.decksService.getSubdecks(deckId))[1].speciesCount, 0);
  });

  test('a shared deck keeps its subdecks', () async {
    await stack.decksService.setActiveSubdecks(deckId, {'l1'});

    final shared = (await stack.decksService.getCreateDeck(deckId)).toJson();
    final reimported = await stack.importService.importDecks([
      CreateDeck.fromJson(shared),
    ]);
    final copyId = reimported.importedDeckIds.single;

    expect(
      (shared['subdecks'] as List).map((s) => (s as Map)['speciesNames']),
      [
        ['Carcharodon carcharias'],
        ['Prionace glauca'],
      ],
    );
    expect(await stack.subdecks.getSubdeckIdBySpeciesId(copyId), {
      _greatWhite: 'l1',
      _blueShark: 'l2',
    });
    // What was switched off is the sharer's choice, not part of the deck.
    expect(
      (await stack.decksService.getSubdecks(copyId)).map((s) => s.isActive),
      [true, true],
    );
  });

  test('a deck without subdecks is shared without the key', () async {
    final flat = await stack.importService.importDecks([
      CreateDeck(
        name: 'Flat',
        description: '',
        speciesNames: {'Rhincodon typus'},
      ),
    ]);

    final shared = (await stack.decksService.getCreateDeck(
      flat.importedDeckIds.single,
    )).toJson();

    expect(shared.containsKey('subdecks'), isFalse);
  });
}
