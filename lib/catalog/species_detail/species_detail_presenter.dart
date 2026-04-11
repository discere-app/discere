import 'package:discere/catalog/common/taxon_classification/taxon_classification_presenter.dart';
import 'package:discere/catalog/model/habitat_tag.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_presenter.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_native_region.dart';
import 'package:discere/catalog/species_detail/species_detail_view_model.dart';
import 'package:discere/catalog/species_detail/species_fact_view_model.dart';
import 'package:discere/catalog/species_detail/species_facts_section_view_model.dart';
import 'package:discere/catalog/species_detail/species_native_region_view_model.dart';
import 'package:discere/catalog/species_detail/species_native_regions_section_view_model.dart';
import 'package:discere/shared/model/language.dart';

import '../../l10n/app_localizations.dart';

class SpeciesDetailPresenter {
  final TaxonIdentityPresenter _identityPresenter;
  final TaxonClassificationPresenter _classificationPresenter;

  const SpeciesDetailPresenter({
    TaxonIdentityPresenter identityPresenter = const TaxonIdentityPresenter(),
    TaxonClassificationPresenter classificationPresenter =
        const TaxonClassificationPresenter(),
  }) : _identityPresenter = identityPresenter,
       _classificationPresenter = classificationPresenter;

  SpeciesDetailViewModel present(
    Species species,
    Language language,
    AppLocalizations loc,
  ) {
    final nativeRegions = _buildNativeRegions(species.nativeRegions);
    final habitatTags = _buildHabitatTags(species, language);

    return SpeciesDetailViewModel(
      identity: _identityPresenter.present(species, language),
      isDeprecated: species.isDeprecated,
      classificationRows: _classificationPresenter.present(
        species.classification,
        language,
      ),
      factsSection: SpeciesFactsSectionViewModel(
        title: loc.speciesDetailFactsTitle,
        facts: _buildFacts(species, loc),
      ),
      nativeRegionsSection: nativeRegions.isEmpty && habitatTags.isEmpty
          ? null
          : SpeciesNativeRegionsSectionViewModel(
              title: 'Regions & habitats',
              nativeRegions: nativeRegions,
              habitatTags: habitatTags,
            ),
    );
  }

  List<SpeciesFactViewModel> _buildFacts(
    Species species,
    AppLocalizations loc,
  ) {
    final facts = <SpeciesFactViewModel>[];

    void addFact(SpeciesFactType type, String label, String? value) {
      if (value == null || value.trim().isEmpty) return;
      facts.add(SpeciesFactViewModel(type: type, label: label, value: value));
    }

    addFact(SpeciesFactType.size, loc.speciesSize, species.size);
    addFact(SpeciesFactType.depth, loc.speciesDepth, species.depth);
    addFact(
      SpeciesFactType.conservation,
      loc.speciesDetailConservation,
      species.conservation,
    );
    addFact(SpeciesFactType.bodyForm, 'Body form', species.bodyShape);
    addFact(SpeciesFactType.humanRisk, 'Human risk', species.dangerousToHumans);
    addFact(
      SpeciesFactType.fishingImportance,
      'Fishing importance',
      species.fisheriesImportance,
    );
    addFact(
      SpeciesFactType.typicalLifespan,
      'Typical lifespan',
      species.longevityYears,
    );
    addFact(
      SpeciesFactType.foodChainLevel,
      'Food-chain level',
      species.trophicLevelFood,
    );

    return facts;
  }

  List<String> _buildHabitatTags(Species species, Language language) {
    final tags = <String>[];

    final habitat = species.habitat?.trim();
    if (habitat != null && habitat.isNotEmpty) {
      final mappedHabitat = HabitatTagEnum.fromRawHabitat(habitat);
      final label = mappedHabitat?.localizedLabel(language) ?? habitat;
      if (!tags.contains(label)) {
        tags.add(label);
      }
    }

    for (final trait in species.traits) {
      final mappedTrait = HabitatTagEnum.fromTraitKey(trait);
      final label = mappedTrait?.localizedLabel(language) ?? _humanizeTrait(trait);
      if (!tags.contains(label)) {
        tags.add(label);
      }
    }

    return tags;
  }

  String _humanizeTrait(String trait) {
    return trait
        .replaceAll('_association', '')
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  List<SpeciesNativeRegionViewModel> _buildNativeRegions(
    List<SpeciesNativeRegion> regions,
  ) {
    final grouped = <String, List<String>>{};

    for (final region in regions) {
      if (region.scope == 'subregion') {
        final parts = region.label.split(' · ');
        final country = parts.first.trim();
        final subregion = parts.length > 1
            ? parts.sublist(1).join(' · ').trim()
            : region.label.trim();
        if (country.isEmpty) continue;
        final subregions = grouped.putIfAbsent(country, () => []);
        if (subregion.isNotEmpty && !subregions.contains(subregion)) {
          subregions.add(subregion);
        }
        continue;
      }

      final country = region.label.trim();
      if (country.isEmpty) continue;
      grouped.putIfAbsent(country, () => []);
    }

    return grouped.entries
        .map(
          (entry) => SpeciesNativeRegionViewModel(
            label: entry.key,
            subregions: List.unmodifiable(entry.value),
          ),
        )
        .toList(growable: false);
  }
}
