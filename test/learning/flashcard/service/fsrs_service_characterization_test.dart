/// Characterisation test for [FsrsService].
///
/// The other FSRS test asserts *properties* ("stability goes up after a
/// successful recall"). This one pins the **complete** resulting stat for
/// every (card state × grade) transition: all six scheduling fields plus the
/// four identity fields, not just the one the path is about.
///
/// That completeness is the point. In a spaced-repetition scheduler a field
/// that silently keeps its old value — or picks up a neighbour's — does not
/// crash; it moves a due date, and surfaces days later as "that card came
/// back far too early". A property test happily passes while that happens,
/// because the property it checks is about a different field.
///
/// Time base: no clock is injected. Every value here is a pure function of
/// the input stat's fields and of `elapsedDays`, which is a whole number of
/// days — so the only non-determinism is the sub-millisecond gap between the
/// `start` timestamp the case takes and the `DateTime.now()` inside the
/// service. Dates are therefore asserted as an *offset from* `start` with a
/// few seconds of slack, while the numbers are asserted exactly. Injecting a
/// clock would buy nothing here and would widen a refactor that is meant to
/// leave behaviour untouched.
library;

import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:flutter_test/flutter_test.dart';

const _defaultSut = FsrsService();
const _multiRelearnSut = FsrsService(
  relearningSteps: [Duration(minutes: 10), Duration(minutes: 30)],
);
const _noStepsSut = FsrsService(learningSteps: [], relearningSteps: []);

/// Builds the card under test. Identity fields carry non-default values so a
/// transition that drops or rewrites one is visible.
FlashcardStat _card(
  DateTime start, {
  double stability = 0.0,
  double difficulty = 0.0,
  CardState cardState = CardState.newCard,
  int stepIndex = 0,
  int? daysSinceReview,
}) {
  return FlashcardStat(
    speciesId: 'sp-1',
    deckId: 'dk-1',
    learningMode: LearningMode.genus,
    nameType: NameType.scientificName,
    stability: stability,
    difficulty: difficulty,
    lastReviewDate: daysSinceReview == null
        ? null
        : start.subtract(Duration(days: daysSinceReview)),
    nextReviewDate: daysSinceReview == null
        ? null
        : start.subtract(const Duration(hours: 1)),
    cardState: cardState,
    stepIndex: stepIndex,
  );
}

/// Registers one transition case: grade [grade] on the card [given] builds,
/// then assert the whole resulting stat.
void _transition(
  String name, {
  FsrsService sut = _defaultSut,
  required FlashcardStat Function(DateTime start) given,
  required ReviewGrade grade,
  required double stability,
  required double difficulty,
  required CardState cardState,
  required int stepIndex,
  required double dueInMinutes,
}) {
  test(name, () {
    final start = DateTime.now();
    final result = sut.reviewCard(given(start), grade);

    expect(result.speciesId, 'sp-1', reason: 'speciesId');
    expect(result.deckId, 'dk-1', reason: 'deckId');
    expect(result.learningMode, LearningMode.genus, reason: 'learningMode');
    expect(result.nameType, NameType.scientificName, reason: 'nameType');
    expect(result.stability, closeTo(stability, 1e-9), reason: 'stability');
    expect(result.difficulty, closeTo(difficulty, 1e-9), reason: 'difficulty');
    expect(result.cardState, cardState, reason: 'cardState');
    expect(result.stepIndex, stepIndex, reason: 'stepIndex');

    expect(result.lastReviewDate, isNotNull, reason: 'lastReviewDate');
    expect(
      result.lastReviewDate!.difference(start).inSeconds.abs(),
      lessThan(5),
      reason: 'lastReviewDate is set to the moment of the review',
    );
    expect(result.nextReviewDate, isNotNull, reason: 'nextReviewDate');
    expect(
      result.nextReviewDate!.difference(start).inMilliseconds / 60000.0,
      closeTo(dueInMinutes, 0.05),
      reason: 'nextReviewDate',
    );
  });
}

void main() {
  // ─── New card ──────────────────────────────────────────────────────────
  // Learning steps are the default [1m, 10m]; Easy skips them entirely.

  group('new card', () {
    FlashcardStat given(DateTime s) => _card(s);

    _transition(
      'Again → learning step 0, 1m',
      given: given,
      grade: ReviewGrade.again,
      stability: 0.0,
      difficulty: 0.0,
      cardState: CardState.learning,
      stepIndex: 0,
      dueInMinutes: 1,
    );
    _transition(
      'Hard → learning step 0, 1m',
      given: given,
      grade: ReviewGrade.hard,
      stability: 0.0,
      difficulty: 0.0,
      cardState: CardState.learning,
      stepIndex: 0,
      dueInMinutes: 1,
    );
    _transition(
      'Good → learning step 1, 10m',
      given: given,
      grade: ReviewGrade.good,
      stability: 0.0,
      difficulty: 0.0,
      cardState: CardState.learning,
      stepIndex: 1,
      dueInMinutes: 10,
    );
    _transition(
      'Easy → review, FSRS initialised from w3',
      given: given,
      grade: ReviewGrade.easy,
      stability: 8.2956,
      difficulty: 1.0,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 11946,
    );
  });

  // ─── Learning card ─────────────────────────────────────────────────────

  group('learning card on step 0', () {
    FlashcardStat given(DateTime s) => _card(
      s,
      cardState: CardState.learning,
      stepIndex: 0,
      daysSinceReview: 0,
    );

    _transition(
      'Again → stays on step 0',
      given: given,
      grade: ReviewGrade.again,
      stability: 0.0,
      difficulty: 0.0,
      cardState: CardState.learning,
      stepIndex: 0,
      dueInMinutes: 1,
    );
    _transition(
      'Hard → repeats step 0',
      given: given,
      grade: ReviewGrade.hard,
      stability: 0.0,
      difficulty: 0.0,
      cardState: CardState.learning,
      stepIndex: 0,
      dueInMinutes: 1,
    );
    _transition(
      'Good → advances to step 1',
      given: given,
      grade: ReviewGrade.good,
      stability: 0.0,
      difficulty: 0.0,
      cardState: CardState.learning,
      stepIndex: 1,
      dueInMinutes: 10,
    );
    _transition(
      'Easy → graduates to review',
      given: given,
      grade: ReviewGrade.easy,
      stability: 8.2956,
      difficulty: 1.0,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 11946,
    );
  });

  group('learning card on the last step', () {
    FlashcardStat given(DateTime s) => _card(
      s,
      cardState: CardState.learning,
      stepIndex: 1,
      daysSinceReview: 0,
    );

    _transition(
      'Again → back to step 0',
      given: given,
      grade: ReviewGrade.again,
      stability: 0.0,
      difficulty: 0.0,
      cardState: CardState.learning,
      stepIndex: 0,
      dueInMinutes: 1,
    );
    _transition(
      'Hard → repeats step 1',
      given: given,
      grade: ReviewGrade.hard,
      stability: 0.0,
      difficulty: 0.0,
      cardState: CardState.learning,
      stepIndex: 1,
      dueInMinutes: 10,
    );
    _transition(
      'Good → graduates, FSRS initialised from w2, stepIndex reset',
      given: given,
      grade: ReviewGrade.good,
      stability: 2.3065,
      difficulty: 2.118103970459015,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 3321,
    );
    _transition(
      'Easy → graduates, FSRS initialised from w3',
      given: given,
      grade: ReviewGrade.easy,
      stability: 8.2956,
      difficulty: 1.0,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 11946,
    );
  });

  // ─── Review card ───────────────────────────────────────────────────────

  group('review card, 3 days elapsed', () {
    FlashcardStat given(DateTime s) => _card(
      s,
      cardState: CardState.review,
      stability: 2.3065,
      difficulty: 5.0,
      daysSinceReview: 3,
    );

    _transition(
      'Again → relearning, stability reduced, difficulty raised',
      given: given,
      grade: ReviewGrade.again,
      stability: 2.1951606304646805,
      difficulty: 8.347534,
      cardState: CardState.relearning,
      stepIndex: 0,
      dueInMinutes: 10,
    );
    _transition(
      'Hard → review, hard penalty on stability',
      given: given,
      grade: ReviewGrade.hard,
      stability: 6.986832279554659,
      difficulty: 6.671767,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 10061,
    );
    _transition(
      'Good → review',
      given: given,
      grade: ReviewGrade.good,
      stability: 10.088894877876054,
      difficulty: 4.996,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 14528,
    );
    _transition(
      'Easy → review, easy bonus on stability',
      given: given,
      grade: ReviewGrade.easy,
      stability: 16.88214736677406,
      difficulty: 3.320233,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 24310,
    );
  });

  group('review card, same day', () {
    // elapsedDays == 0 takes the short-term stability path instead of the
    // recall/forgetting formulas.
    FlashcardStat given(DateTime s) => _card(
      s,
      cardState: CardState.review,
      stability: 2.3065,
      difficulty: 5.0,
      daysSinceReview: 0,
    );

    _transition(
      'Again → relearning, short-term stability drop',
      given: given,
      grade: ReviewGrade.again,
      stability: 0.7750839828558983,
      difficulty: 8.347534,
      cardState: CardState.relearning,
      stepIndex: 0,
      dueInMinutes: 10,
    );
    _transition(
      'Hard → review, stability held (sinc floored at 1)',
      given: given,
      grade: ReviewGrade.hard,
      stability: 2.3065,
      difficulty: 6.671767,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 3321,
    );
    _transition(
      'Good → review, stability held',
      given: given,
      grade: ReviewGrade.good,
      stability: 2.3065,
      difficulty: 4.996,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 3321,
    );
    _transition(
      'Easy → review, stability raised',
      given: given,
      grade: ReviewGrade.easy,
      stability: 3.9460540679694778,
      difficulty: 3.320233,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 5682,
    );
  });

  // ─── Relearning card ───────────────────────────────────────────────────
  // Relearning runs on step timers only: stability and difficulty were
  // already updated on the lapse and must survive untouched.

  group('relearning card, single step', () {
    FlashcardStat given(DateTime s) => _card(
      s,
      cardState: CardState.relearning,
      stability: 1.2,
      difficulty: 6.0,
      stepIndex: 0,
      daysSinceReview: 0,
    );

    _transition(
      'Again → back to step 0',
      given: given,
      grade: ReviewGrade.again,
      stability: 1.2,
      difficulty: 6.0,
      cardState: CardState.relearning,
      stepIndex: 0,
      dueInMinutes: 10,
    );
    _transition(
      'Hard → repeats step 0',
      given: given,
      grade: ReviewGrade.hard,
      stability: 1.2,
      difficulty: 6.0,
      cardState: CardState.relearning,
      stepIndex: 0,
      dueInMinutes: 10,
    );
    _transition(
      'Good → back to review on the carried-over stability',
      given: given,
      grade: ReviewGrade.good,
      stability: 1.2,
      difficulty: 6.0,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 1728,
    );
    _transition(
      'Easy → back to review immediately',
      given: given,
      grade: ReviewGrade.easy,
      stability: 1.2,
      difficulty: 6.0,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 1728,
    );
  });

  group('relearning card, two steps, on step 0', () {
    FlashcardStat given(DateTime s) => _card(
      s,
      cardState: CardState.relearning,
      stability: 1.2,
      difficulty: 6.0,
      stepIndex: 0,
      daysSinceReview: 0,
    );

    _transition(
      'Again → step 0',
      sut: _multiRelearnSut,
      given: given,
      grade: ReviewGrade.again,
      stability: 1.2,
      difficulty: 6.0,
      cardState: CardState.relearning,
      stepIndex: 0,
      dueInMinutes: 10,
    );
    _transition(
      'Hard → repeats step 0',
      sut: _multiRelearnSut,
      given: given,
      grade: ReviewGrade.hard,
      stability: 1.2,
      difficulty: 6.0,
      cardState: CardState.relearning,
      stepIndex: 0,
      dueInMinutes: 10,
    );
    _transition(
      'Good → advances to step 1',
      sut: _multiRelearnSut,
      given: given,
      grade: ReviewGrade.good,
      stability: 1.2,
      difficulty: 6.0,
      cardState: CardState.relearning,
      stepIndex: 1,
      dueInMinutes: 30,
    );
    _transition(
      'Easy → back to review',
      sut: _multiRelearnSut,
      given: given,
      grade: ReviewGrade.easy,
      stability: 1.2,
      difficulty: 6.0,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 1728,
    );
  });

  group('relearning card, two steps, on the last step', () {
    FlashcardStat given(DateTime s) => _card(
      s,
      cardState: CardState.relearning,
      stability: 1.2,
      difficulty: 6.0,
      stepIndex: 1,
      daysSinceReview: 0,
    );

    _transition(
      'Again → back to step 0',
      sut: _multiRelearnSut,
      given: given,
      grade: ReviewGrade.again,
      stability: 1.2,
      difficulty: 6.0,
      cardState: CardState.relearning,
      stepIndex: 0,
      dueInMinutes: 10,
    );
    _transition(
      'Hard → repeats step 1',
      sut: _multiRelearnSut,
      given: given,
      grade: ReviewGrade.hard,
      stability: 1.2,
      difficulty: 6.0,
      cardState: CardState.relearning,
      stepIndex: 1,
      dueInMinutes: 30,
    );
    _transition(
      'Good → back to review, stepIndex reset',
      sut: _multiRelearnSut,
      given: given,
      grade: ReviewGrade.good,
      stability: 1.2,
      difficulty: 6.0,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 1728,
    );
    _transition(
      'Easy → back to review, stepIndex reset',
      sut: _multiRelearnSut,
      given: given,
      grade: ReviewGrade.easy,
      stability: 1.2,
      difficulty: 6.0,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 1728,
    );
  });

  // ─── Without learning/relearning steps ─────────────────────────────────

  group('no learning steps, new card', () {
    // Without steps, anything below Easy is graded as Good on graduation.
    FlashcardStat given(DateTime s) => _card(s);

    for (final grade in [
      ReviewGrade.again,
      ReviewGrade.hard,
      ReviewGrade.good,
    ]) {
      _transition(
        '${grade.name} → review with Good\'s initial FSRS values',
        sut: _noStepsSut,
        given: given,
        grade: grade,
        stability: 2.3065,
        difficulty: 2.118103970459015,
        cardState: CardState.review,
        stepIndex: 0,
        dueInMinutes: 3321,
      );
    }
    _transition(
      'Easy → review with Easy\'s initial FSRS values',
      sut: _noStepsSut,
      given: given,
      grade: ReviewGrade.easy,
      stability: 8.2956,
      difficulty: 1.0,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 11946,
    );
  });

  group('no relearning steps, review card', () {
    FlashcardStat given(DateTime s) => _card(
      s,
      cardState: CardState.review,
      stability: 2.3065,
      difficulty: 5.0,
      daysSinceReview: 3,
    );

    _transition(
      'Again → stays in review, scheduled from the reduced stability',
      sut: _noStepsSut,
      given: given,
      grade: ReviewGrade.again,
      stability: 2.1951606304646805,
      difficulty: 8.347534,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 3161,
    );
  });

  // ─── Normalisation of values coming back from the database ─────────────

  group('numerical guards', () {
    _transition(
      'stability 0 falls back to w0',
      given: (s) => _card(
        s,
        cardState: CardState.review,
        stability: 0,
        difficulty: 5,
        daysSinceReview: 1,
      ),
      grade: ReviewGrade.good,
      stability: 2.402839975826301,
      difficulty: 4.996,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 3460,
    );
    _transition(
      'infinite stability falls back to w0',
      given: (s) => _card(
        s,
        cardState: CardState.review,
        stability: double.infinity,
        difficulty: 5,
        daysSinceReview: 1,
      ),
      grade: ReviewGrade.good,
      stability: 2.402839975826301,
      difficulty: 4.996,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 3460,
    );
    _transition(
      'difficulty 0 clamps to 1',
      given: (s) => _card(
        s,
        cardState: CardState.review,
        stability: 5,
        difficulty: 0,
        daysSinceReview: 1,
      ),
      grade: ReviewGrade.good,
      stability: 10.448672781263424,
      difficulty: 1.0,
      cardState: CardState.review,
      stepIndex: 0,
      dueInMinutes: 15046,
    );
    _transition(
      'difficulty above 10 clamps to 10',
      given: (s) => _card(
        s,
        cardState: CardState.review,
        stability: 5,
        difficulty: 42,
        daysSinceReview: 1,
      ),
      grade: ReviewGrade.again,
      stability: 4.758639996671754,
      difficulty: 9.991,
      cardState: CardState.relearning,
      stepIndex: 0,
      dueInMinutes: 10,
    );
  });

  // ─── Preview must not schedule the card ────────────────────────────────

  group('previewIntervals', () {
    test('leaves the stat it was given completely untouched', () {
      final start = DateTime.now();
      final stat = _card(
        start,
        cardState: CardState.review,
        stability: 2.3065,
        difficulty: 5.0,
        daysSinceReview: 3,
      );
      final before = (
        stability: stat.stability,
        difficulty: stat.difficulty,
        lastReviewDate: stat.lastReviewDate,
        nextReviewDate: stat.nextReviewDate,
        cardState: stat.cardState,
        stepIndex: stat.stepIndex,
      );

      _defaultSut.previewIntervals(stat);

      expect(stat.stability, before.stability);
      expect(stat.difficulty, before.difficulty);
      expect(stat.lastReviewDate, before.lastReviewDate);
      expect(stat.nextReviewDate, before.nextReviewDate);
      expect(stat.cardState, before.cardState);
      expect(stat.stepIndex, before.stepIndex);
    });

    test('previews every grade from the card it is given', () {
      final start = DateTime.now();
      final stat = _card(
        start,
        cardState: CardState.review,
        stability: 2.3065,
        difficulty: 5.0,
        daysSinceReview: 3,
      );

      expect(_defaultSut.previewIntervals(stat), {
        ReviewGrade.again: '10m',
        ReviewGrade.hard: '6d',
        ReviewGrade.good: '10d',
        ReviewGrade.easy: '2w',
      });
    });
  });
}
