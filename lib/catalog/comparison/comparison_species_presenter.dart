import 'package:discere/catalog/common/species_facts/species_fact_view_model.dart';
import 'package:discere/catalog/common/species_facts/species_facts_presenter.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/comparison/comparison_species_view_model.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';

class ComparisonSpeciesPresenter {
  /// Of the detail page's facts, the ones that set similar species apart at a
  /// glance; the primary habitat joins them.
  static const _comparedFactTypes = {
    SpeciesFactType.size,
    SpeciesFactType.depth,
  };

  final SpeciesListItemPresenter _namesPresenter;
  final SpeciesFactsPresenter _factsPresenter;

  const ComparisonSpeciesPresenter({
    SpeciesListItemPresenter namesPresenter = const SpeciesListItemPresenter(),
    SpeciesFactsPresenter factsPresenter = const SpeciesFactsPresenter(),
  }) : _namesPresenter = namesPresenter,
       _factsPresenter = factsPresenter;

  ComparisonSpeciesViewModel present(
    Species species,
    Language language,
    AppLocalizations loc,
  ) {
    final names = _namesPresenter.presentSpecies(species, language);
    final habitat = _factsPresenter.habitatTags(species, loc).firstOrNull;
    return ComparisonSpeciesViewModel(
      primaryName: names.primaryName,
      scientificName: names.scientificName,
      facts: [
        for (final fact in _factsPresenter.facts(species, loc))
          if (_comparedFactTypes.contains(fact.type)) fact,
        if (habitat != null)
          SpeciesFactViewModel(
            type: SpeciesFactType.habitat,
            label: loc.speciesDetailHabitat,
            value: habitat,
          ),
      ],
    );
  }
}
