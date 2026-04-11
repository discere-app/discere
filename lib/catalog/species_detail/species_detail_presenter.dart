import 'package:discere/catalog/common/taxon_classification/taxon_classification_presenter.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_presenter.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_native_region.dart';
import 'package:discere/catalog/species_detail/species_detail_view_model.dart';
import 'package:discere/catalog/species_detail/species_fact_view_model.dart';
import 'package:discere/catalog/species_detail/species_facts_section_view_model.dart';
import 'package:discere/catalog/species_detail/species_native_region_view_model.dart';
import 'package:discere/catalog/species_detail/species_native_regions_section_view_model.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/depth_format.dart';
import 'package:discere/shared/util/length_format.dart';
import 'package:discere/shared/util/vulnerability_format.dart';

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
    final habitatTags = _buildHabitatTags(species);

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

    addFact(
      SpeciesFactType.size,
      loc.speciesSize,
      formatLengthCm(species.maxLengthCm),
    );
    addFact(
      SpeciesFactType.depth,
      loc.speciesDepth,
      formatDepthRangeM(species.depthMinM, species.depthMaxM),
    );
    addFact(
      SpeciesFactType.conservation,
      loc.speciesDetailConservation,
      formatVulnerability(species.conservation),
    );
    addFact(
      SpeciesFactType.bodyForm,
      'Body form',
      species.bodyShape?.label,
    );
    addFact(
      SpeciesFactType.humanRisk,
      'Human risk',
      species.dangerousToHumans?.label ?? species.dangerousToHumansRaw,
    );
    addFact(
      SpeciesFactType.fishingImportance,
      'Fishing importance',
      species.fisheriesImportance?.label,
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

  List<String> _buildHabitatTags(Species species) {
    final tags = <String>[];

    final habitat = species.habitatTag?.label ?? species.habitat?.trim();
    if (habitat != null && habitat.isNotEmpty) {
      if (!tags.contains(habitat)) {
        tags.add(habitat);
      }
    }

    for (final trait in species.traits) {
      if (!tags.contains(trait.label)) {
        tags.add(trait.label);
      }
    }

    return tags;
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
