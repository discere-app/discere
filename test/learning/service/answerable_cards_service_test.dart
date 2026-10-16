import 'dart:io';

import 'package:discere/catalog/repository/taxon_assignment_repository.dart';
import 'package:discere/learning/flashcard/service/flashcard_review_service.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/repository/flashcard_stat_mode_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/service/answerable_cards_service.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../mocks.mocks.dart';
import '../../support/in_memory_user_database.dart';

/// A species without an answer in a learning mode is no card there, against
/// real databases: a copy of the reference fixture and an in-memory user
/// database.
///
/// In family mode two species of the deck have no answer: Kynaria cynara
/// sits under the placeholder family "Not assigned", and Amphiprion
/// ocellaris loses its family, cut from its genus in the copy. Three sharks
/// have one. In species mode all five do.
const _deckId = 'deck-1';
const _placeholderFamily = 'discere:species:92182'; // Kynaria cynara
const _noFamily = 'discere:species:6002'; // Amphiprion ocellaris
const _sharks = {
  'discere:species:694', // Carcharodon carcharias
  'discere:species:834', // Prionace glauca
  'discere:species:847', // Sphyrna lewini
};
const _withoutAnswer = {_placeholderFamily, _noFamily};

const _family = DeckConfig(deckId: _deckId, learningMode: LearningMode.family);
const _species = DeckConfig(deckId: _deckId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDir;
  late Database referenceDb;
  late Database userDb;
  late FlashcardStatRepository stats;
  late FlashcardStatModeRepository modeStats;
  late AnswerableCardsService answerableCards;
  late MockSpeciesMediaService media;
  late FlashcardReviewService review;
  late String amphiprionFamily;

  Future<void> addRows(Set<String> speciesIds, LearningMode mode) =>
      stats.insertOrUpdateFlashcardStats({
        for (final id in speciesIds)
          FlashcardStat(speciesId: id, deckId: _deckId, learningMode: mode),
      });

  Future<FlashcardStat?> rowOf(String speciesId, LearningMode mode) =>
      stats.getFlashcardStat(speciesId, _deckId, mode);

  Future<Set<String>> initializedIn(LearningMode mode) async => {
    for (final MapEntry(key: id, value: date)
        in (await modeStats.getNextReviewDates(
          _deckId,
          mode,
          NameType.commonName,
        )).entries)
      if (date != null) id,
  };

  /// A row as a past review left it: due, with FSRS state.
  FlashcardStat reviewed(String speciesId, LearningMode mode) => FlashcardStat(
    speciesId: speciesId,
    deckId: _deckId,
    learningMode: mode,
    stability: 4.2,
    difficulty: 5.1,
    lastReviewDate: DateTime(2026, 9, 1),
    nextReviewDate: DateTime(2026, 9, 3),
    cardState: CardState.review,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('answerable_cards');
    final path = p.join(tempDir.path, 'reference.db');
    await File('test/fixtures/discere_reference_test.db').copy(path);
    referenceDb = await databaseFactoryFfi.openDatabase(path);
    amphiprionFamily =
        (await referenceDb.query(
              'genera',
              columns: ['family'],
              where: 'id = ?',
              whereArgs: ['discere:genus:5106'],
            )).single['family']
            as String;
    await referenceDb.update(
      'genera',
      {'family': null},
      where: 'id = ?',
      whereArgs: ['discere:genus:5106'], // Amphiprion
    );

    userDb = await openInMemoryUserDatabase();
    await userDb.insert('decks', {
      'id': _deckId,
      'name': 'Reef',
      'description': '',
    });
    stats = FlashcardStatRepository(database: userDb);
    modeStats = FlashcardStatModeRepository(database: userDb);
    answerableCards = AnswerableCardsService(
      stats,
      modeStats,
      TaxonAssignmentRepository(database: referenceDb),
    );
    media = MockSpeciesMediaService();
    // The tests look at which species a session asks for, not at the cards.
    when(media.resolveAllFromCache(any)).thenAnswer((_) async => []);
    review = FlashcardReviewService(
      stats,
      media,
      MockSpeciesPhotoGapAckRepository(),
      modeStats: modeStats,
      answerableCards: answerableCards,
      userDataWrites: UserDataWrites(),
    );
    await addRows({..._withoutAnswer, ..._sharks}, LearningMode.species);
  });

  tearDown(() async {
    await userDb.close();
    await referenceDb.close();
    await tempDir.delete(recursive: true);
  });

  test('finds the species without an answer in family mode, and none in '
      'species mode', () async {
    expect(
      await answerableCards.speciesWithoutAnswer(_deckId, LearningMode.family),
      _withoutAnswer,
    );
    expect(
      await answerableCards.speciesWithoutAnswer(_deckId, LearningMode.species),
      isEmpty,
    );
  });

  test('in family mode a species without an answer is neither initialized, '
      'counted nor due', () async {
    await review.initializeNextBatch(_deckId, _family);

    expect(await initializedIn(LearningMode.family), _sharks);
    final stat = await answerableCards.deckStat(
      _deckId,
      learningMode: LearningMode.family,
      nameType: NameType.commonName,
    );
    expect(
      (stat.totalCount, stat.uninitializedCount, stat.dueCount),
      (3, 0, 3),
    );
    await review.getFlashCardsForReview(_deckId, _family);
    verify(media.resolveAllFromCache(_sharks)).called(1);
  });

  test(
    'in species mode both count and are initialized like any other',
    () async {
      await review.initializeNextBatch(_deckId, _species);

      expect(await initializedIn(LearningMode.species), {
        ..._withoutAnswer,
        ..._sharks,
      });
      final stat = await answerableCards.deckStat(
        _deckId,
        learningMode: LearningMode.species,
        nameType: NameType.commonName,
      );
      expect(
        (stat.totalCount, stat.uninitializedCount, stat.dueCount),
        (5, 0, 5),
      );
    },
  );

  test('a species with rows only in the mode it has no answer in stays in '
      'the deck', () async {
    await userDb.delete(
      'flashcard_stats',
      where: 'species_id = ?',
      whereArgs: [_placeholderFamily],
    );
    await stats.insertOrUpdateFlashcardStats({
      reviewed(_placeholderFamily, LearningMode.family),
    });

    await review.getFlashCardsForReview(_deckId, _family);
    await review.initializeNextBatch(_deckId, _family);

    expect(
      await stats.getSpeciesIdsByDeckId(_deckId),
      contains(_placeholderFamily),
    );
    final row = await rowOf(_placeholderFamily, LearningMode.family);
    expect(row!.nextReviewDate, DateTime(2026, 9, 3));
    expect(row.stability, 4.2);
  });

  test('a scheduled row without an answer is neither counted nor handed out, '
      'and keeps its learning state', () async {
    await stats.insertOrUpdateFlashcardStats({
      reviewed(_noFamily, LearningMode.family),
      reviewed('discere:species:694', LearningMode.family),
    });

    final stat = await answerableCards.deckStat(
      _deckId,
      learningMode: LearningMode.family,
      nameType: NameType.commonName,
    );
    await review.getFlashCardsForReview(_deckId, _family);

    expect(
      (stat.totalCount, stat.uninitializedCount, stat.dueCount),
      (3, 2, 1),
    );
    verify(media.resolveAllFromCache({'discere:species:694'})).called(1);
    final kept = await rowOf(_noFamily, LearningMode.family);
    expect(kept!.nextReviewDate, DateTime(2026, 9, 3));
    expect(kept.lastReviewDate, DateTime(2026, 9, 1));
    expect((kept.stability, kept.difficulty), (4.2, 5.1));
    expect(kept.cardState, CardState.review);
  });

  test('a species that gains its answer again carries on from its stored '
      'learning state', () async {
    await stats.insertOrUpdateFlashcardStats({
      reviewed(_noFamily, LearningMode.family),
    });
    await referenceDb.update(
      'genera',
      {'family': amphiprionFamily},
      where: 'id = ?',
      whereArgs: ['discere:genus:5106'],
    );

    final stat = await answerableCards.deckStat(
      _deckId,
      learningMode: LearningMode.family,
      nameType: NameType.commonName,
    );
    await review.getFlashCardsForReview(_deckId, _family);

    expect(
      (stat.totalCount, stat.uninitializedCount, stat.dueCount),
      (4, 3, 1),
    );
    verify(media.resolveAllFromCache({_noFamily})).called(1);
    expect((await rowOf(_noFamily, LearningMode.family))!.stability, 4.2);
  });

  test('reminders count only the cards of each deck\'s active mode, without '
      'the species that have no answer in it', () async {
    await userDb.insert('deck_config', {
      'deck_id': _deckId,
      'learning_mode': LearningMode.family.storageValue,
    });
    await stats.insertOrUpdateFlashcardStats({
      reviewed(_noFamily, LearningMode.family),
      reviewed('discere:species:694', LearningMode.family),
      reviewed('discere:species:834', LearningMode.species),
    });

    expect(await answerableCards.reviewDatesOfCards(), [DateTime(2026, 9, 3)]);
  });

  test('batches of one initialize every species with an answer, however '
      'many without one sort first', () async {
    for (var batch = 0; batch < _sharks.length; batch++) {
      await review.initializeNextBatch(_deckId, _family, batchSize: 1);
    }

    expect(await initializedIn(LearningMode.family), _sharks);
    expect(
      await modeStats.getUninitializedStats(
        _deckId,
        LearningMode.family,
        NameType.commonName,
        limit: 1,
        excludedSpeciesIds: _withoutAnswer,
      ),
      isEmpty,
    );
  });
}
