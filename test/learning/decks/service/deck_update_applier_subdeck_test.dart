import 'package:discere/catalog/repository/deprecated_species_name_repository.dart';
import 'package:discere/learning/decks/service/deck_update_applier.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/learning_test_stack.dart';

/// A deck update brings the subdecks in line with the catalog entry, by
/// subdeck id, whatever the user decides about the species — against real
/// databases.
const _greatWhite = 'discere:species:694';
const _blueShark = 'discere:species:834';
const _whaleShark = 'discere:species:1872';

CreateDeck _entry(String json) => CreateDeck.fromJsonString(json);

const _installed = '''
{
  "name": "Sharks", "description": "", "sourceId": "sharks",
  "updatedAt": "2026-01-01T00:00:00Z",
  "speciesNames": ["Carcharodon carcharias", "Prionace glauca",
                   "Rhincodon typus"],
  "subdecks": [
    {"id": "l1", "name": "Level 1",
     "speciesNames": ["Carcharodon carcharias", "Prionace glauca"]},
    {"id": "l2", "name": "Level 2", "speciesNames": ["Rhincodon typus"]}
  ]
}
''';

/// Same species: the blue shark moves up a level, Level 1 is renamed,
/// Level 2 goes away and Level 3 is new.
const _restructured = '''
{
  "name": "Sharks", "description": "", "sourceId": "sharks",
  "updatedAt": "2026-02-01T00:00:00Z",
  "speciesNames": ["Carcharodon carcharias", "Prionace glauca",
                   "Rhincodon typus"],
  "subdecks": [
    {"id": "l1", "name": "Beginner",
     "speciesNames": ["Carcharodon carcharias"]},
    {"id": "l3", "name": "Level 3", "speciesNames": ["Prionace glauca"]}
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LearningTestStack stack;
  late DeckUpdateApplier applier;
  late String deckId;

  setUp(() async {
    stack = await LearningTestStack.open();
    applier = DeckUpdateApplier(
      stack.decksService,
      stack.speciesRepository,
      deprecatedNames: DeprecatedSpeciesNameRepository(
        database: stack.referenceDb,
      ),
      userDataWrites: stack.writes,
    );
    deckId = (await stack.importService.importDecks([
      _entry(_installed),
    ])).importedDeckIds.single;
  });

  tearDown(() => stack.close());

  Future<void> update(
    CreateDeck remote, {
    bool includeAdditions = true,
    bool includeRemovals = true,
  }) async {
    final diff = await applier.diff(deckId, remote);
    await applier.apply(
      deckId: deckId,
      remote: remote,
      diff: diff,
      includeAdditions: includeAdditions,
      includeRemovals: includeRemovals,
    );
  }

  test('an update that only restructures the subdecks still applies '
      'them', () async {
    await stack.decksService.setActiveSubdecks(deckId, {'l2'});
    final remote = _entry(_restructured);
    expect((await applier.diff(deckId, remote)).hasChanges, isFalse);

    await update(remote);

    expect(
      (await stack.decksService.getSubdecks(
        deckId,
      )).map((s) => (s.id, s.name, s.isActive)),
      [
        // Renamed, and still switched off.
        ('l1', 'Beginner', false),
        // New, so on.
        ('l3', 'Level 3', true),
      ],
    );
    expect(await stack.subdecks.getSubdeckIdBySpeciesId(deckId), {
      _greatWhite: 'l1',
      _blueShark: 'l3',
    });
    // Level 2 is gone; the whale shark stays in the deck, in no subdeck.
    expect(
      await stack.stats.getSpeciesIdsByDeckId(deckId),
      contains(_whaleShark),
    );
  });

  test('declined additions get no place in a subdeck, declined removals '
      'keep theirs only where the catalog still has one', () async {
    final remote = _entry('''
    {
      "name": "Sharks", "description": "", "sourceId": "sharks",
      "updatedAt": "2026-02-01T00:00:00Z",
      "speciesNames": ["Carcharodon carcharias", "Galeocerdo cuvier"],
      "subdecks": [
        {"id": "l1", "name": "Level 1",
         "speciesNames": ["Carcharodon carcharias", "Galeocerdo cuvier"]}
      ]
    }
    ''');

    await update(remote, includeAdditions: false, includeRemovals: false);

    expect(await stack.subdecks.getSubdeckIdBySpeciesId(deckId), {
      _greatWhite: 'l1',
    });
    expect(await stack.stats.getSpeciesIdsByDeckId(deckId), {
      _greatWhite,
      _blueShark,
      _whaleShark,
    });
  });

  Future<Map<String, String>> unresolvedNameRows() async => {
    for (final row in await stack.userDb.query(
      'deck_subdeck_unresolved_names',
    ))
      row['name'] as String: row['subdeck_id'] as String,
  };

  const withUnresolvedAddition = '''
  {
    "name": "Sharks", "description": "", "sourceId": "sharks",
    "updatedAt": "2026-02-01T00:00:00Z",
    "speciesNames": ["Carcharodon carcharias", "Prionace glauca",
                     "Rhincodon typus", "Zzz unknownus"],
    "subdecks": [
      {"id": "l1", "name": "Level 1",
       "speciesNames": ["Carcharodon carcharias", "Zzz unknownus"]}
    ]
  }
  ''';

  test('a declined unresolved addition keeps no place in a subdeck', () async {
    await update(_entry(withUnresolvedAddition), includeAdditions: false);

    expect(await unresolvedNameRows(), isEmpty);
  });

  test('an accepted unresolved addition waits in its subdeck', () async {
    await update(_entry(withUnresolvedAddition));

    expect(await unresolvedNameRows(), {'Zzz unknownus': 'l1'});
  });

  test('an entry without subdecks leaves the deck without', () async {
    await update(
      _entry('''
      {
        "name": "Sharks", "description": "", "sourceId": "sharks",
        "updatedAt": "2026-02-01T00:00:00Z",
        "speciesNames": ["Carcharodon carcharias", "Prionace glauca",
                         "Rhincodon typus"]
      }
      '''),
    );

    expect(await stack.decksService.getSubdecks(deckId), isEmpty);
  });
}
