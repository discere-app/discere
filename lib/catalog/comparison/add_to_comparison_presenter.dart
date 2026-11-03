import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/l10n/app_localizations.dart';

/// What the "add to comparison" sheet derives from the species it was opened
/// for.
class AddToComparisonPresenter {
  /// How many names the suggested list name spells out before it counts the
  /// rest — enough to recognise the list by, short enough for one line.
  static const _namedSpecies = 2;

  const AddToComparisonPresenter();

  /// The name a new list starts with: the species' names, the first
  /// [_namedSpecies] of them and the number of the others.
  String suggestedName(Set<String> speciesNames, AppLocalizations loc) {
    final named = speciesNames.take(_namedSpecies).join(', ');
    final others = speciesNames.length - _namedSpecies;
    return others > 0 ? loc.comparisonNameSuggestionMore(named, others) : named;
  }

  /// Those of [speciesIds] that [list] does not hold yet.
  Set<String> missingFrom(ComparisonList list, Set<String> speciesIds) =>
      speciesIds.difference(list.speciesIds.toSet());

  /// Whether [list] already holds every one of [speciesIds], so adding them
  /// would change nothing.
  bool containsAll(ComparisonList list, Set<String> speciesIds) =>
      missingFrom(list, speciesIds).isEmpty;
}
