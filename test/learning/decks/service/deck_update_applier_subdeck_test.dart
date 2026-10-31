import 'package:discere/catalog/repository/deprecated_species_name_repository.dart';
import 'package:discere/learning/decks/service/deck_update_applier.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/subdeck_edit.dart';
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
    bool adoptCatalogSubdecks = false,
  }) async {
    final diff = await applier.diff(deckId, remote);
    await applier.apply(
      deckId: deckId,
      remote: remote,
      diff: diff,
      includeAdditions: includeAdditions,
      includeRemovals: includeRemovals,
      adoptCatalogSubdecks: adoptCatalogSubdecks,
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

  group('a deck the user divided up differently', () {
    /// Level 2 renamed and first, a subdeck of the user's on its heels, Level
    /// 1 switched off; the blue shark moved to the user's subdeck.
    setUp(() async {
      await stack.decksService.editSubdecks(
        deckId,
        const SubdeckEdit(
          subdecks: [
            (id: 'l2', name: 'Big ones'),
            (id: 'mine', name: 'Mine'),
            (id: 'l1', name: 'Level 1'),
          ],
          moves: {_blueShark: 'mine'},
        ),
      );
      await stack.decksService.setActiveSubdecks(deckId, {'l2', 'mine'});
    });

    Future<List<(String, String, bool)>> headings() async => [
      for (final s in await stack.decksService.getSubdecks(deckId))
        (s.id, s.name, s.isActive),
    ];

    const ownHeadings = [
      ('l2', 'Big ones', true),
      ('mine', 'Mine', true),
      ('l1', 'Level 1', false),
    ];

    test('the diff says so', () async {
      final diff = await applier.diff(deckId, _entry(_restructured));

      expect(diff.hasCustomizedSubdecks, isTrue);
    });

    test('keeps its division through an update', () async {
      await update(_entry(_restructured));

      expect(await headings(), ownHeadings);
      expect(await stack.subdecks.getSubdeckIdBySpeciesId(deckId), {
        _greatWhite: 'l1',
        _blueShark: 'mine',
        _whaleShark: 'l2',
      });
      expect(await stack.decksService.hasCustomizedSubdecks(deckId), isTrue);
    });

    /// Adds the tiger shark to Level 2 and the hammerhead to one this deck
    /// lacks, and a name waiting in each; drops the great white.
    final withAdditions = _entry('''
    {
      "name": "Sharks", "description": "", "sourceId": "sharks",
      "updatedAt": "2026-02-01T00:00:00Z",
      "speciesNames": ["Prionace glauca", "Rhincodon typus",
                       "Galeocerdo cuvier", "Sphyrna lewini",
                       "Zzz inlevel", "Zzz elsewhere"],
      "subdecks": [
        {"id": "l2", "name": "Level 2",
         "speciesNames": ["Prionace glauca", "Galeocerdo cuvier",
                          "Zzz inlevel"]},
        {"id": "l9", "name": "Level 9",
         "speciesNames": ["Sphyrna lewini", "Zzz elsewhere"]}
      ]
    }
    ''');

    const tigerShark = 'discere:species:822';
    const hammerhead = 'discere:species:847';

    test('what the update adds goes into the subdeck of the same id, else '
        'into none; what it removes leaves', () async {
      await update(withAdditions);

      expect(await stack.subdecks.getSubdeckIdBySpeciesId(deckId), {
        // The catalog has the blue shark in Level 2; the user's place stands.
        _blueShark: 'mine',
        _whaleShark: 'l2',
        tigerShark: 'l2',
      });
      expect(
        await stack.stats.getSpeciesIdsByDeckId(deckId),
        containsAll([tigerShark, hammerhead]),
      );
      expect(await unresolvedNameRows(), {'Zzz inlevel': 'l2'});
      expect(await headings(), ownHeadings);
    });

    test('declined additions get no place, and no waiting name', () async {
      await update(withAdditions, includeAdditions: false);

      expect(
        (await stack.subdecks.getSubdeckIdBySpeciesId(
          deckId,
        )).containsKey(tigerShark),
        isFalse,
      );
      expect(await unresolvedNameRows(), isEmpty);
    });

    test('a name already waiting stays where it waits', () async {
      await stack.userDb.insert('deck_subdeck_unresolved_names', {
        'deck_id': deckId,
        'name': 'Zzz inlevel',
        'subdeck_id': 'mine',
      });

      await update(withAdditions);

      expect(await unresolvedNameRows(), {'Zzz inlevel': 'mine'});
    });

    test('adopting the catalog takes its division and clears the mark', () async {
      await update(_entry(_restructured), adoptCatalogSubdecks: true);

      expect(await headings(), [
        // Switched off before, and kept so by its id.
        ('l1', 'Beginner', false),
        ('l3', 'Level 3', true),
      ]);
      expect(await stack.subdecks.getSubdeckIdBySpeciesId(deckId), {
        _greatWhite: 'l1',
        _blueShark: 'l3',
      });
      expect(await stack.decksService.hasCustomizedSubdecks(deckId), isFalse);
    });
  });

  test('a deck that only had its switches changed follows the catalog, '
      'with or without the option', () async {
    await stack.decksService.setActiveSubdecks(deckId, {'l1'});
    final remote = _entry(_restructured);
    expect((await applier.diff(deckId, remote)).hasCustomizedSubdecks, isFalse);

    await update(remote);

    expect(
      (await stack.decksService.getSubdecks(deckId)).map((s) => s.id),
      ['l1', 'l3'],
    );
  });
}
