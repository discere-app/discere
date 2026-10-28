import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'test_utils.dart';

const _level1SourceId = '3f0c5a2e-6d1b-4c7a-9e21-0b8d4f6a1c01';
const _level2SourceId = '3f0c5a2e-6d1b-4c7a-9e21-0b8d4f6a1c02';
const _reefSourceId = '3f0c5a2e-6d1b-4c7a-9e21-0b8d4f6a1c00';

const _level1Name = 'Reef - Level 1';
const _level2Name = 'Reef - Level 2';
const _reefName = 'Reef';

const _clownfish = 'Amphiprion ocellaris';
const _whiteShark = 'Carcharodon carcharias';
const _whaleShark = 'Rhincodon typus';

/// The catalog before the levels were joined: two decks, sharing the white
/// shark, so both hold a card for it once imported.
final _catalogWithLevels = [
  {
    'name': _level1Name,
    'description': '',
    'sourceId': _level1SourceId,
    'updatedAt': '2026-09-01T00:00:00Z',
    'speciesNames': [_clownfish, _whiteShark],
  },
  {
    'name': _level2Name,
    'description': '',
    'sourceId': _level2SourceId,
    'updatedAt': '2026-09-01T00:00:00Z',
    'speciesNames': [_whiteShark, _whaleShark],
  },
];

/// The catalog after: one deck with the levels as subdecks, superseding
/// both level decks, which are gone from it.
final _catalogJoined = [
  {
    'name': _reefName,
    'description': '',
    'sourceId': _reefSourceId,
    'updatedAt': '2026-10-01T00:00:00Z',
    'speciesNames': [_clownfish, _whiteShark, _whaleShark],
    'subdecks': [
      {
        'id': 'level-1',
        'name': 'Level 1',
        'speciesNames': [_clownfish, _whiteShark],
      },
      {
        'id': 'level-2',
        'name': 'Level 2',
        'speciesNames': [_whaleShark],
      },
    ],
    'supersedes': [_level1SourceId, _level2SourceId],
  },
];

/// Review state written onto one card, recognisable after it has moved.
typedef _Progress = ({
  int lastReview,
  int nextReview,
  double stability,
  double difficulty,
  int cardState,
});

Future<void> _openOnlineTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('main_fab')));
  await safePumpAndSettle(tester);
  await tester.tap(find.byIcon(Icons.download_for_offline_outlined).first);
  // pump() first: the Online tab opens with a loading spinner.
  await tester.pump(const Duration(milliseconds: 500));
  await safePumpAndSettle(tester);
}

Future<String> _deckIdBySourceId(String sourceId) async {
  final db = await DatabaseHelper.userDb;
  final rows = await db.query(
    'decks',
    columns: ['id'],
    where: 'sourceId = ?',
    whereArgs: [sourceId],
  );
  return rows.single['id']! as String;
}

/// The reference ID of every species [deckId] holds, by scientific name.
Future<Map<String, String>> _speciesIdsByName(
  WidgetTester tester,
  String deckId,
) async {
  final decksService = Provider.of<DecksService>(
    tester.element(find.byType(MaterialApp)),
    listen: false,
  );
  return {
    for (final species in await decksService.getSpeciesByDeckId(deckId))
      species.getBinomialName(): species.id,
  };
}

/// Writes [progress] onto every card [deckId] holds for [speciesId].
Future<void> _review(
  String deckId,
  String speciesId,
  _Progress progress,
) async {
  final db = await DatabaseHelper.userDb;
  final updated = await db.update(
    'flashcard_stats',
    {
      'last_review_date': progress.lastReview,
      'next_review_date': progress.nextReview,
      'stability': progress.stability,
      'difficulty': progress.difficulty,
      'card_state': progress.cardState,
    },
    where: 'deck_id = ? AND species_id = ?',
    whereArgs: [deckId, speciesId],
  );
  expect(updated, 1, reason: 'the import gives each species one card');
}

Future<Map<String, Object?>> _card(String deckId, String speciesId) async {
  final db = await DatabaseHelper.userDb;
  final rows = await db.query(
    'flashcard_stats',
    where: 'deck_id = ? AND species_id = ?',
    whereArgs: [deckId, speciesId],
  );
  return rows.single;
}

Matcher _hasProgress(_Progress progress) => allOf(
  containsPair('last_review_date', progress.lastReview),
  containsPair('next_review_date', progress.nextReview),
  containsPair('stability', progress.stability),
  containsPair('difficulty', progress.difficulty),
  containsPair('card_state', progress.cardState),
);

void main() {
  initializeIntegrationTest();

  group('deck merge', () {
    setUp(() async {
      await resetTestState();
    });

    testWidgets('joining level decks into one moves their progress to it', (
      tester,
    ) async {
      var catalog = _catalogWithLevels;
      final client = deckCatalogClient(() => catalog);
      await startApp(
        tester,
        notificationService: createMockNotificationService(),
        httpClient: client,
      );

      // Import both level decks from the online tab, so they carry their
      // sourceIds.
      await _openOnlineTab(tester);
      for (final name in [_level1Name, _level2Name]) {
        await tester.tap(find.byKey(ValueKey('deck-checkbox-$name')));
        await safePumpAndSettle(tester);
      }
      await tester.tap(find.byKey(const ValueKey('import_online_button')));
      await tester.pump(const Duration(milliseconds: 500));
      await dismissDownloadDialog(tester);
      await waitForFinder(tester, find.text(_level1Name));
      await waitForFinder(tester, find.text(_level2Name));

      // Progress: the clownfish in level 1, and the white shark in both
      // levels — reviewed later in level 2, which is the card to keep.
      final level1Id = await _deckIdBySourceId(_level1SourceId);
      final level2Id = await _deckIdBySourceId(_level2SourceId);
      final level1Species = await _speciesIdsByName(tester, level1Id);
      final clownfishId = level1Species[_clownfish]!;
      final whiteSharkId = level1Species[_whiteShark]!;
      final day = const Duration(days: 1).inMilliseconds;
      final now = DateTime.now().millisecondsSinceEpoch;
      final clownfishProgress = (
        lastReview: now - 3 * day,
        nextReview: now + 5 * day,
        stability: 4.5,
        difficulty: 6.25,
        cardState: 2,
      );
      final staleSharkProgress = (
        lastReview: now - 10 * day,
        nextReview: now + 20 * day,
        stability: 1.5,
        difficulty: 8.5,
        cardState: 3,
      );
      final recentSharkProgress = (
        lastReview: now - day,
        nextReview: now + 2 * day,
        stability: 9.75,
        difficulty: 3.5,
        cardState: 2,
      );
      await _review(level1Id, clownfishId, clownfishProgress);
      await _review(level1Id, whiteSharkId, staleSharkProgress);
      await _review(level2Id, whiteSharkId, recentSharkProgress);

      final db = await DatabaseHelper.userDb;
      Future<int> sortOrderOf(String deckId) async =>
          (await db.query(
                'decks',
                columns: ['sortOrder'],
                where: 'id = ?',
                whereArgs: [deckId],
              )).single['sortOrder']!
              as int;
      final level1SortOrder = await sortOrderOf(level1Id);
      expect(
        level1SortOrder,
        lessThan(await sortOrderOf(level2Id)),
        reason: 'level 1 comes first in the deck list',
      );

      // The catalog joins the levels. The online tab fetches it every
      // time it opens, and offers the merge for the entry.
      catalog = _catalogJoined;
      await _openOnlineTab(tester);
      final mergeButton = find.byKey(
        const ValueKey('import-online-merge-$_reefName'),
      );
      await waitForFinder(
        tester,
        mergeButton,
        description: 'the merge offer on the joined entry',
      );
      await tester.tap(mergeButton);
      await safePumpAndSettle(tester);
      final confirm = find.byKey(const Key('deck_merge_confirm_button'));
      await waitForFinder(tester, confirm, description: 'the merge dialog');
      // Both levels hold a species the user was learning, so both are
      // suggested; the user takes level 2 out.
      final level2Checkbox = find.byKey(
        const Key('deck_merge_subdeck_checkbox_level-2'),
      );
      for (final id in ['level-1', 'level-2']) {
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(Key('deck_merge_subdeck_checkbox_$id')),
              )
              .value,
          isTrue,
          reason: '$id is suggested',
        );
      }
      await tester.ensureVisible(level2Checkbox);
      await safePumpAndSettle(tester);
      await tester.tap(level2Checkbox);
      await safePumpAndSettle(tester);
      await tester.tap(confirm);
      await tester.pump(const Duration(milliseconds: 500));
      await dismissDownloadDialog(tester);
      await waitForAbsence(
        tester,
        find.byKey(const ValueKey('import-online-merge-$_reefName')),
        description: 'the merge offer to go once merged',
      );

      // The level decks are gone, the joined deck is there with both
      // levels as subdecks, and only the chosen one on.
      final decks = await db.query(
        'decks',
        columns: ['id', 'name', 'sourceId', 'sortOrder'],
      );
      expect(decks, hasLength(1));
      final reef = decks.single;
      expect(reef['name'], _reefName);
      expect(reef['sourceId'], _reefSourceId);
      final reefId = reef['id']! as String;
      final subdecks = await db.query(
        'deck_subdecks',
        columns: ['subdeck_id', 'is_active'],
        where: 'deck_id = ?',
        whereArgs: [reefId],
        orderBy: 'sort_order',
      );
      expect(subdecks, [
        {'subdeck_id': 'level-1', 'is_active': 1},
        {'subdeck_id': 'level-2', 'is_active': 0},
      ]);

      // Progress followed the species; of the two white shark cards, the
      // one reviewed last stayed.
      expect(await _card(reefId, clownfishId), _hasProgress(clownfishProgress));
      expect(
        await _card(reefId, whiteSharkId),
        _hasProgress(recentSharkProgress),
      );

      // The joined deck took level 1's place in the deck list.
      expect(reef['sortOrder'], level1SortOrder);

      // And the deck list shows it.
      await tester.pageBack();
      await safePumpAndSettle(tester);
      await waitForFinder(tester, find.text(_reefName));
      expect(find.text(_level1Name), findsNothing);
      expect(find.text(_level2Name), findsNothing);
    }, timeout: integrationTestTimeout);
  });
}
