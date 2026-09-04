import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/learning/flashcard/answer_options_presenter.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';

/// Builds the candidate name pool multiple-choice distractors are drawn from
/// for a given card. Prefers species already in the user's deck
/// ([AnswerOptionsPresenter.taxonomicPoolFromDeck]); only queries the full
/// reference database, escalating rank by rank, when the deck itself doesn't
/// have enough taxonomically-close relatives.
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
    int minimumDistinctNames = 3,
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
    final excludeId = switch (learningMode) {
      LearningMode.species => currentSpecies.id,
      LearningMode.genus => classification.genusId,
      LearningMode.family => classification.familyId,
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
            .where((result) => result.id != excludeId)
            .map((result) => _labelFor(result, language, nameType)),
      );
      if (deduplicateCommonNames(collected).length >= minimumDistinctNames) {
        break;
      }
    }

    return deduplicateCommonNames(collected);
  }

  String _labelFor(SearchResult result, Language language, NameType nameType) {
    if (nameType == NameType.scientificName) return result.name;
    final commonNames = resolveCommonNames(result.commonNames, language);
    return commonNames.isNotEmpty ? commonNames.first : result.name;
  }
}
