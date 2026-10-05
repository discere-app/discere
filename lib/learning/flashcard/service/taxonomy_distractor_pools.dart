import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/flashcard/answer_options_presenter.dart';
import 'package:discere/learning/flashcard/service/multiple_choice_distractor_pool_service.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/shared/model/language.dart';

/// The distractor name pools of one multiple-choice review session, built on
/// first use and kept per taxonomic scope.
///
/// Cards sharing a scope — the rank above the one being tested, see
/// [_scopeIdFor] — share a pool, so the pool is the right unit to cache, but
/// building every scope's pool up front makes
/// opening a deck pay for cards the user may never reach, since
/// [MultipleChoiceDistractorPoolService.buildPool] queries the reference
/// database whenever the deck itself holds too few close relatives. Built
/// per scope on demand, a card costs only its own scope, and each scope is
/// paid for once per session.
///
/// A pool is built for whichever card of its scope asks first, yet has to
/// serve all of them. It does, because it is the scope's pool rather than
/// that card's: it holds the scope's own deck species too, and — as far as
/// the deck has them — enough distinct names that every card keeps its
/// distractors after dropping its own (see
/// [AnswerOptionsPresenter.minimumPoolSize]).
///
/// Session-scoped by construction: it holds the deck's species and the
/// configuration the pools were derived from, so a changed deck or
/// configuration means a new instance rather than an invalidated cache.
class TaxonomyDistractorPools {
  final MultipleChoiceDistractorPoolService _poolService;
  final AnswerOptionsPresenter _answerOptionsPresenter;
  final List<Species> _deckSpecies;
  final LearningMode _learningMode;
  final NameType _nameType;
  final Language _language;

  final Map<String, Future<List<String>>> _poolByScopeId = {};
  List<String>? _deckWidePool;

  TaxonomyDistractorPools({
    required MultipleChoiceDistractorPoolService poolService,
    required List<Species> deckSpecies,
    required LearningMode learningMode,
    required NameType nameType,
    required Language language,
    AnswerOptionsPresenter answerOptionsPresenter =
        const AnswerOptionsPresenter(),
  }) : _poolService = poolService,
       _deckSpecies = deckSpecies,
       _learningMode = learningMode,
       _nameType = nameType,
       _language = language,
       _answerOptionsPresenter = answerOptionsPresenter;

  /// The names [species]'s distractors are drawn from.
  Future<List<String>> poolFor(Species species) {
    final scopeId = _scopeIdFor(species);
    if (scopeId == null) return Future.value(_deckWideNames());
    return _poolByScopeId.putIfAbsent(
      scopeId,
      () => _poolService.buildPool(
        currentSpecies: species,
        deckSpecies: _deckSpecies,
        learningMode: _learningMode,
        language: _language,
        nameType: _nameType,
      ),
    );
  }

  /// These pools for the deck without [speciesId], starting over: a pool
  /// built before may hold the removed species' name from the deck, which
  /// would keep offering it as a distractor after it left the deck.
  TaxonomyDistractorPools withoutSpecies(String speciesId) =>
      TaxonomyDistractorPools(
        poolService: _poolService,
        deckSpecies: _deckSpecies
            .where((species) => species.id != speciesId)
            .toList(),
        learningMode: _learningMode,
        nameType: _nameType,
        language: _language,
        answerOptionsPresenter: _answerOptionsPresenter,
      );

  /// The ancestor id whose pool [species] draws from: its genus in species
  /// mode, its family in genus mode, its order in family mode. `null` when the
  /// species is missing that classification id (e.g. an imported species
  /// without full reference-DB linkage) — such a card falls back to the
  /// whole-deck pool.
  String? _scopeIdFor(Species species) => switch (_learningMode) {
    LearningMode.species => species.classification.genusId,
    LearningMode.genus => species.classification.familyId,
    LearningMode.family => species.classification.orderId,
  };

  /// The distinct primary names of the whole deck — the fallback for a species
  /// that carries no scope id. Computed on first use for the same reason the
  /// scoped pools are: a session where every card has a scope never needs it.
  List<String> _deckWideNames() =>
      _deckWidePool ??= _answerOptionsPresenter.distinctPrimaryNames(
        _deckSpecies,
        _language,
        _learningMode,
        _nameType,
      );
}
