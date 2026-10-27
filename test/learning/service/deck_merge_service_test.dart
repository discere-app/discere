import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/create_subdeck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/repository/deck_merge_repository.dart';
import 'package:discere/learning/service/deck_merge_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/learning_test_stack.dart';

const _greatWhite = 'Carcharodon carcharias';
const _blueShark = 'Prionace glauca';
const _hammerhead = 'Sphyrna lewini';
const _tigerShark = 'Galeocerdo cuvier';
const _whaleShark = 'Rhincodon typus';
const _clownfish = 'Amphiprion ocellaris';

CreateDeck _deck(
  String sourceId,
  List<String> speciesNames, {
  List<String>? supersedes,
  List<CreateSubdeck>? subdecks,
  LearningMode? learningMode,
}) => CreateDeck(
  name: 'Deck $sourceId',
  description: '',
  sourceId: sourceId,
  speciesNames: speciesNames.toSet(),
  supersedes: supersedes,
  subdecks: subdecks,
  learningMode: learningMode,
);

/// One catalog entry joining two levels, with a subdeck for each and one
/// for a species neither level had.
final _joined = _deck(
  'all',
  [_greatWhite, _blueShark, _whaleShark, _hammerhead],
  supersedes: ['level-1', 'level-2'],
  subdecks: [
    CreateSubdeck(id: 's1', name: 'One', speciesNames: {_greatWhite}),
    CreateSubdeck(id: 's2', name: 'Two', speciesNames: {_whaleShark}),
    CreateSubdeck(id: 's3', name: 'New', speciesNames: {_hammerhead}),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LearningTestStack stack;
  late FavoriteService favorites;
  late DeckMergeService service;

  Future<String> import(CreateDeck deck) async =>
      (await stack.importService.importDecks([deck])).importedDeckIds.single;

  Future<void> review(String deckId, String name, double stability) =>
      stack.userDb.update(
        'flashcard_stats',
        {'stability': stability, 'last_review_date': 1000},
        where: 'deck_id = ? AND species_id = ?',
        whereArgs: [deckId, fixtureSpeciesIds[name]],
      );

  /// Every card's deck, species name and stability.
  Future<Set<(String, String, double)>> cards() async {
    final namesById = {
      for (final MapEntry(:key, :value) in fixtureSpeciesIds.entries)
        value: key,
    };
    final rows = await stack.userDb.query('flashcard_stats');
    return {
      for (final row in rows)
        (
          row['deck_id'] as String,
          namesById[row['species_id']]!,
          row['stability'] as double,
        ),
    };
  }

  Future<Set<String>> deckSourceIds() async =>
      (await stack.decksService.getDecksBySourceId()).keys.toSet();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    stack = await LearningTestStack.open();
    favorites = FavoriteService(await SharedPreferences.getInstance());
    service = DeckMergeService(
      stack.decksService,
      stack.importService,
      mergeRepository: DeckMergeRepository(database: stack.userDb),
      subdeckRepository: stack.subdecks,
      deckConfigRepository: stack.deckConfigs,
      favoriteService: favorites,
      userDataWrites: stack.writes,
    );
  });

  tearDown(() => stack.close());

  group('two levels joined into one new entry', () {
    late String level1;
    late String level2;

    setUp(() async {
      await import(_deck('unrelated', [_clownfish]));
      level1 = await import(_deck('level-1', [_greatWhite, _blueShark]));
      level2 = await import(_deck('level-2', [_whaleShark, _tigerShark]));
      await review(level1, _greatWhite, 5);
      await review(level2, _whaleShark, 7);
      await review(level2, _tigerShark, 3);
      await stack.deckConfigs.save(
        DeckConfig(deckId: level1, learningMode: LearningMode.genus),
      );
      favorites.toggleDeck(level2);
    });

    test('the plan names both levels as going and the species the entry '
        'drops as lost', () async {
      final plan = await service.plan(_joined, [_joined]);

      expect(plan.target, isNull);
      expect(plan.superseded.map((d) => d.id), [level1, level2]);
      expect(plan.deleted.map((d) => d.id), [level1, level2]);
      expect(plan.lostSpeciesNames, [_tigerShark]);
    });

    test('the merge imports the entry, moves the progress, takes over the '
        'first level\'s settings and place, and deletes both', () async {
      final positionOfLevel1 = (await stack.userDb.query(
        'decks',
        where: 'id = ?',
        whereArgs: [level1],
      )).single['sortOrder'];

      final merged = await service.merge(
        await service.plan(_joined, [_joined]),
      );
      final target = merged.targetDeckId;

      expect(merged.importResult?.importedDeckIds, [target]);
      expect(await deckSourceIds(), {'unrelated', 'all'});
      expect(
        (await cards()).where((card) => card.$1 == target),
        unorderedEquals([
          (target, _greatWhite, 5.0),
          (target, _blueShark, 0.0),
          (target, _whaleShark, 7.0),
          (target, _hammerhead, 0.0),
        ]),
      );
      expect(
        (await stack.deckConfigs.getOrDefault(target)).learningMode,
        LearningMode.genus,
      );
      expect(
        (await stack.userDb.query(
          'decks',
          where: 'id = ?',
          whereArgs: [target],
        )).single['sortOrder'],
        positionOfLevel1,
      );
      expect(favorites.isFavoriteDeck(target), isTrue);
    });

    test('the first level\'s settings win over the ones the entry brings for '
        'a new deck', () async {
      await stack.deckConfigs.save(DeckConfig(deckId: level1));
      final genusEntry = _deck(
        'all',
        [_greatWhite, _blueShark, _whaleShark, _hammerhead],
        supersedes: ['level-1', 'level-2'],
        learningMode: LearningMode.genus,
      );

      final merged = await service.merge(
        await service.plan(genusEntry, [genusEntry]),
      );
      await stack.settled();

      expect(
        (await stack.deckConfigs.getOrDefault(
          merged.targetDeckId,
        )).learningMode,
        LearningMode.species,
      );
    });

    test('of the target\'s subdecks only those the moved species are in '
        'stay switched on', () async {
      final merged = await service.merge(
        await service.plan(_joined, [_joined]),
      );

      final subdecks = await stack.decksService.getSubdecks(
        merged.targetDeckId,
      );
      expect(subdecks.map((s) => (s.id, s.isActive)), [
        ('s1', true),
        ('s2', true),
        ('s3', false),
      ]);
    });

    test('a merge that stopped half way is finished by merging again, with '
        'nothing moved twice', () async {
      // Imported and level 1 moved, then the app was closed.
      final target = await import(_joined);
      await DeckMergeRepository(
        database: stack.userDb,
      ).moveSharedProgress(fromDeckId: level1, toDeckId: target);

      final plan = await service.plan(_joined, [_joined]);
      expect(plan.target?.id, target);
      final merged = await service.merge(plan);

      expect(merged.targetDeckId, target);
      expect(merged.importResult, isNull);
      expect(await deckSourceIds(), {'unrelated', 'all'});
      expect(
        (await cards()).where((card) => card.$1 == target),
        unorderedEquals([
          (target, _greatWhite, 5.0),
          (target, _blueShark, 0.0),
          (target, _whaleShark, 7.0),
          (target, _hammerhead, 0.0),
        ]),
      );
    });

    test(
      'an entry already imported keeps its own settings and subdecks',
      () async {
        final target = await import(_joined);
        await stack.decksService.setActiveSubdecks(target, {'s3'});

        await service.merge(await service.plan(_joined, [_joined]));

        expect(
          (await stack.deckConfigs.getOrDefault(target)).learningMode,
          LearningMode.species,
        );
        // Moved species switch their subdecks on; the user's own choice stays.
        final subdecks = await stack.decksService.getSubdecks(target);
        expect(subdecks.map((s) => (s.id, s.isActive)), [
          ('s1', true),
          ('s2', true),
          ('s3', true),
        ]);
      },
    );
  });

  group('one deck split into two entries', () {
    final sharks = _deck(
      'sharks',
      [_greatWhite, _whaleShark],
      supersedes: ['old'],
    );
    final fish = _deck('fish', [_clownfish], supersedes: ['old']);
    final catalog = [sharks, fish];
    late String old;

    setUp(() async {
      old = await import(_deck('old', [_greatWhite, _whaleShark, _clownfish]));
      await review(old, _greatWhite, 5);
      await review(old, _clownfish, 2);
    });

    test('the first merge keeps the deck for the species the other entry '
        'takes', () async {
      final plan = await service.plan(sharks, catalog);
      expect(plan.deleted, isEmpty);
      expect(plan.lostSpeciesNames, isEmpty);

      final merged = await service.merge(plan);

      expect(await deckSourceIds(), {'old', 'sharks'});
      expect(await cards(), {
        (merged.targetDeckId, _greatWhite, 5.0),
        (merged.targetDeckId, _whaleShark, 0.0),
        (old, _clownfish, 2.0),
      });
    });

    test('the second merge takes the rest and deletes the deck', () async {
      final sharksId = (await service.merge(
        await service.plan(sharks, catalog),
      )).targetDeckId;

      final plan = await service.plan(fish, catalog);
      expect(plan.deleted.map((d) => d.id), [old]);
      expect(plan.lostSpeciesNames, isEmpty);
      final fishId = (await service.merge(plan)).targetDeckId;

      expect(await deckSourceIds(), {'sharks', 'fish'});
      expect(await cards(), {
        (sharksId, _greatWhite, 5.0),
        (sharksId, _whaleShark, 0.0),
        (fishId, _clownfish, 2.0),
      });
    });
  });
}
