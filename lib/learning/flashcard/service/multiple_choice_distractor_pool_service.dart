import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/learning/flashcard/answer_options_presenter.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';

/// Builds the candidate name pool multiple-choice distractors are drawn from
/// for a given card, closest relatives first: species already in the user's
/// deck ([AnswerOptionsPresenter.taxonomicPoolFromDeck]); then the full
/// reference database, escalating rank by rank up to the class, when the
/// deck itself doesn't have enough taxonomically-close relatives; and as a
/// last resort the rest of the deck, whatever its taxonomy.
///
/// The last stage is what makes multiple choice hold for every card of a
/// deck the deck editor allows it for: such a deck has at least
/// [AnswerOptionsPresenter.minimumPoolSize] distinct names, so even a
/// species without enough relatives in the reference database gets a full
/// pool.
class MultipleChoiceDistractorPoolService {
  final AnswerOptionsPresenter _answerOptionsPresenter;
  final TaxonomyRepository _taxonomyRepository;

  const MultipleChoiceDistractorPoolService({
    required TaxonomyRepository taxonomyRepository,
    AnswerOptionsPresenter answerOptionsPresenter =
        const AnswerOptionsPresenter(),
  }) : _taxonomyRepository = taxonomyRepository,
       _answerOptionsPresenter = answerOptionsPresenter;

  Future<List<String>> buildPool({
    required Species currentSpecies,
    required List<Species> deckSpecies,
    required LearningMode learningMode,
    required Language language,
    required NameType nameType,
    int minimumDistinctNames = AnswerOptionsPresenter.minimumPoolSize,
  }) async {
    final deckPool = _answerOptionsPresenter.taxonomicPoolFromDeck(
      currentSpecies: currentSpecies,
      deckSpecies: deckSpecies,
      language: language,
      learningMode: learningMode,
      nameType: nameType,
      minimumDistinctNames: minimumDistinctNames,
    );
    if (deckPool.length >= minimumDistinctNames) return deckPool;

    final classification = currentSpecies.classification;
    final targetType = switch (learningMode) {
      LearningMode.species => SearchEntityType.species,
      LearningMode.genus => SearchEntityType.genus,
      LearningMode.family => SearchEntityType.family,
    };
    // Every deck group the reference database could return is in the pool
    // already, under the name its card shows: the deck stage only falls
    // short after walking the same rank chain up to the class without
    // stopping, so it has collected every deck species sharing one of these
    // ancestors. Its reference row would add it a second time under the
    // reference database's name — for the card of that very species a
    // second correct answer posing as a wrong one, since the pool is shared
    // by its whole scope.
    final deckGroupIds = {
      for (final species in [currentSpecies, ...deckSpecies])
        _answerOptionsPresenter.groupIdOf(learningMode, species),
    };
    final scopeChain = switch (learningMode) {
      LearningMode.species => [
        (classification.genusId, SearchEntityType.genus),
        (classification.familyId, SearchEntityType.family),
        (classification.orderId, SearchEntityType.order),
        (classification.classId, SearchEntityType.classType),
      ],
      LearningMode.genus => [
        (classification.familyId, SearchEntityType.family),
        (classification.orderId, SearchEntityType.order),
        (classification.classId, SearchEntityType.classType),
      ],
      LearningMode.family => [
        (classification.orderId, SearchEntityType.order),
        (classification.classId, SearchEntityType.classType),
      ],
    };

    final collected = [...deckPool];
    for (final (scopeId, scopeType) in scopeChain) {
      if (scopeId == null) continue;
      final descendants = await _taxonomyRepository.getDescendantsOfType(
        targetType,
        SearchResult(
          id: scopeId,
          name: '',
          commonNames: const {},
          type: scopeType,
        ),
      );
      collected.addAll(
        descendants
            .where((result) => !deckGroupIds.contains(result.id))
            .map((result) => _labelFor(result, language, nameType)),
      );
      if (deduplicateCommonNames(collected).length >= minimumDistinctNames) {
        break;
      }
    }

    final relatives = deduplicateCommonNames(collected);
    if (relatives.length >= minimumDistinctNames) return relatives;

    return deduplicateCommonNames([
      ...relatives,
      ..._answerOptionsPresenter.distinctPrimaryNames(
        deckSpecies,
        language,
        learningMode,
        nameType,
      ),
    ]);
  }

  String _labelFor(SearchResult result, Language language, NameType nameType) {
    if (nameType == NameType.scientificName) return result.name;
    final commonNames = resolveCommonNames(result.commonNames, language);
    return commonNames.isNotEmpty ? commonNames.first : result.name;
  }
}
