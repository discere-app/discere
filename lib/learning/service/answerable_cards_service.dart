import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/repository/taxon_assignment_repository.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/repository/flashcard_stat_mode_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/repository/subdeck_repository.dart';

/// Which of a deck's species are cards in a learning mode.
///
/// Two kinds of species are no card: one in a subdeck the user switched off,
/// and one without an answer in the mode ([LearningMode.hasNoAnswerFor]) —
/// no genus in genus mode, no family or a placeholder family in family mode.
/// Such a species is never initialized, never counted, never due, never in
/// a reminder. Its rows are only left out when read, never changed: they
/// are what makes it a member of the deck, and they carry a learning state
/// that may well be real. Switching the subdeck back on carries on from that
/// state, and so does a species that gains its answer again — a release
/// whose data drops a rank by mistake must not cost it.
///
/// Neither is stored as a property of the card. Which species have no
/// answer is the reference database's answer, and a new reference database
/// can change it; which subdecks are on is the user's, and a switch changes
/// it. So it is worked out again for every question: from the deck's
/// species and subdecks in the user database and the ranks the reference
/// database leaves unassigned for them, nothing more.
class AnswerableCardsService {
  final FlashcardStatRepository _stats;
  final FlashcardStatModeRepository _modeStats;
  final TaxonAssignmentRepository _assignments;
  final SubdeckRepository _subdecks;

  const AnswerableCardsService(
    this._stats,
    this._modeStats,
    this._assignments,
    this._subdecks,
  );

  /// The species of [deckId] that are no card in [learningMode]. In species
  /// mode, which asks nothing a species could lack, only those in a
  /// switched-off subdeck, and that costs no lookup in the reference
  /// database.
  Future<Set<String>> speciesWithoutCard(
    String deckId,
    LearningMode learningMode,
  ) async {
    final inactive = await _subdecks.getSpeciesIdsInInactiveSubdecks(deckId);
    if (learningMode.askedRank == null) return inactive;
    return _withoutCardAmong(
      await _stats.getSpeciesIdsByDeckId(deckId),
      inactive,
      learningMode,
    );
  }

  /// The species of [deckId] outside its switched-off subdecks — those that
  /// are a card in some learning mode.
  Future<Set<String>> activeSpecies(String deckId) async {
    final species = await _stats.getSpeciesIdsByDeckId(deckId);
    return species.difference(
      await _subdecks.getSpeciesIdsInInactiveSubdecks(deckId),
    );
  }

  /// [FlashcardStatRepository.getDeckStat], counting only the cards of
  /// [learningMode].
  ///
  /// Counted from the mode's rows themselves once some species are left
  /// out: a row of such a species may carry a review date from before it
  /// stopped being a card, and must not count as initialized or due.
  Future<DeckStat> deckStat(
    String deckId, {
    required LearningMode learningMode,
    required NameType nameType,
  }) async {
    Future<DeckStat> allSpecies() => _stats.getDeckStat(
      deckId,
      learningMode: learningMode,
      nameType: nameType,
    );
    final inactive = await _subdecks.getSpeciesIdsInInactiveSubdecks(deckId);
    if (inactive.isEmpty && learningMode.askedRank == null) {
      return allSpecies();
    }

    final deckSpecies = await _stats.getSpeciesIdsByDeckId(deckId);
    final withoutCard = await _withoutCardAmong(
      deckSpecies,
      inactive,
      learningMode,
    );
    if (withoutCard.isEmpty) return allSpecies();

    final cards = deckSpecies.difference(withoutCard);
    final reviewDates = await _modeStats.getNextReviewDates(
      deckId,
      learningMode,
      nameType,
    );
    final now = DateTime.now();
    var initialized = 0;
    var due = 0;
    for (final speciesId in cards) {
      final nextReview = reviewDates[speciesId];
      if (nextReview == null) continue;
      initialized++;
      if (!nextReview.isAfter(now)) due++;
    }
    return DeckStat(cards.length, cards.length - initialized, due);
  }

  /// The review dates a reminder counts, across all decks: those of the
  /// cards of each deck's active learning mode and name type. A row of a
  /// mode the deck is not in, of a species in a switched-off subdeck, or of
  /// a species without an answer in the mode, is no card due.
  ///
  /// Runs whenever a session ends, for every deck at once, so it costs two
  /// queries on the user database — the rows, and the species of every
  /// switched-off subdeck — and, only when some deck is in genus or family
  /// mode, one lookup of those decks' species in the reference database.
  Future<List<DateTime>> reviewDatesOfCards() async {
    final inactiveByDeckId = await _subdecks
        .getSpeciesIdsInInactiveSubdecksByDeckId();
    final rows = [
      for (final row in await _modeStats.getActiveModeReviewDates())
        if (!(inactiveByDeckId[row.deckId]?.contains(row.speciesId) ?? false))
          row,
    ];
    final asking = {
      for (final row in rows)
        if (row.learningMode.askedRank != null) row.speciesId,
    };
    final unassigned = asking.isEmpty
        ? const <String, Set<TaxonRank>>{}
        : await _assignments.unassignedRanksOf(asking);
    return [
      for (final row in rows)
        if (!row.learningMode.hasNoAnswerGiven(
          unassigned[row.speciesId] ?? const {},
        ))
          row.due,
    ];
  }

  /// The rule itself: of [deckSpecies], those in a switched-off subdeck
  /// ([inactive]) and those without an answer in [learningMode].
  Future<Set<String>> _withoutCardAmong(
    Set<String> deckSpecies,
    Set<String> inactive,
    LearningMode learningMode,
  ) async {
    if (learningMode.askedRank == null) return inactive;
    return {
      ...inactive,
      ...await _withoutAnswerAmong(
        deckSpecies.difference(inactive),
        learningMode,
      ),
    };
  }

  Future<Set<String>> _withoutAnswerAmong(
    Set<String> speciesIds,
    LearningMode learningMode,
  ) async {
    final unassigned = await _assignments.unassignedRanksOf(speciesIds);
    return {
      for (final MapEntry(key: speciesId, value: ranks) in unassigned.entries)
        if (learningMode.hasNoAnswerGiven(ranks)) speciesId,
    };
  }
}
