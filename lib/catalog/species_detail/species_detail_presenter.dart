import 'package:discere/catalog/common/continent_label.dart';
import 'package:discere/catalog/common/species_facts/species_facts_presenter.dart';
import 'package:discere/catalog/common/taxon_classification/taxon_classification_presenter.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_presenter.dart';
import 'package:discere/catalog/model/continent.dart';
import 'package:discere/catalog/model/region_abundance.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_native_region.dart';
import 'package:discere/catalog/species_detail/species_detail_view_model.dart';
import 'package:discere/catalog/species_detail/species_facts_section_view_model.dart';
import 'package:discere/catalog/species_detail/species_native_region_view_model.dart';
import 'package:discere/catalog/species_detail/species_native_regions_section_view_model.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';

class SpeciesDetailPresenter {
  final TaxonIdentityPresenter _identityPresenter;
  final TaxonClassificationPresenter _classificationPresenter;
  final SpeciesFactsPresenter _factsPresenter;

  const SpeciesDetailPresenter({
    TaxonIdentityPresenter identityPresenter = const TaxonIdentityPresenter(),
    TaxonClassificationPresenter classificationPresenter =
        const TaxonClassificationPresenter(),
    SpeciesFactsPresenter factsPresenter = const SpeciesFactsPresenter(),
  }) : _identityPresenter = identityPresenter,
       _classificationPresenter = classificationPresenter,
       _factsPresenter = factsPresenter;

  SpeciesDetailViewModel present(
    Species species,
    Language language,
    AppLocalizations loc,
  ) {
    final builtRegions = _buildNativeRegions(species.nativeRegions, loc);
    final habitatTags = _factsPresenter.habitatTags(species, loc);

    return SpeciesDetailViewModel(
      identity: _identityPresenter.present(species, language),
      isDeprecated: species.isDeprecated,
      classificationRows: _classificationPresenter.present(species, language),
      factsSection: SpeciesFactsSectionViewModel(
        title: loc.speciesDetailFactsTitle,
        facts: _factsPresenter.facts(species, loc),
      ),
      nativeRegionsSection: builtRegions.regions.isEmpty && habitatTags.isEmpty
          ? null
          : SpeciesNativeRegionsSectionViewModel(
              title: loc.speciesDetailRegionsHabitatsTitle,
              nativeRegions: builtRegions.regions,
              habitatTags: habitatTags,
              continents: builtRegions.continents,
              bestAbundance: builtRegions.regions.isEmpty
                  ? null
                  : RegionAbundance.best(
                      species.nativeRegions.map((r) => r.abundance).nonNulls,
                    ),
            ),
    );
  }

  static const int _manyCountriesThreshold = 10;

  ({List<SpeciesNativeRegionViewModel> regions, List<String> continents})
  _buildNativeRegions(List<SpeciesNativeRegion> regions, AppLocalizations loc) {
    final subregionsByCountry = <String, List<String>>{};
    final isEndemicByCountry = <String, bool>{};
    final continentsSeen = <Continent>{};

    void markEndemic(String country, SpeciesNativeRegion region) {
      if (region.establishmentStatus?.toLowerCase().contains('endemic') ??
          false) {
        isEndemicByCountry[country] = true;
      } else {
        isEndemicByCountry.putIfAbsent(country, () => false);
      }
    }

    for (final region in regions) {
      if (region.continent != null) {
        continentsSeen.add(region.continent!);
      }

      if (region.scope == 'subregion') {
        // A label with no " · " separator means the subdivision code had no
        // curated name (resolveCountryRegionLabel already dropped it) — the
        // country itself still counts as a native region, just without a
        // subregion pill.
        final parts = region.label.split(' · ');
        final country = parts.first.trim();
        if (country.isEmpty) continue;
        final subregions = subregionsByCountry.putIfAbsent(country, () => []);
        if (parts.length > 1) {
          final subregion = parts.sublist(1).join(' · ').trim();
          if (subregion.isNotEmpty && !subregions.contains(subregion)) {
            subregions.add(subregion);
          }
        }
        markEndemic(country, region);
        continue;
      }

      final country = region.label.trim();
      if (country.isEmpty) continue;
      subregionsByCountry.putIfAbsent(country, () => []);
      markEndemic(country, region);
    }

    final isWidespread = subregionsByCountry.length > _manyCountriesThreshold;
    final builtRegions = subregionsByCountry.entries
        .map(
          (entry) => SpeciesNativeRegionViewModel(
            label: entry.key,
            subregions: isWidespread
                ? const []
                : List.unmodifiable(entry.value),
            isEndemic: isEndemicByCountry[entry.key] ?? false,
          ),
        )
        .toList(growable: false);

    return (
      regions: builtRegions,
      continents: isWidespread
          ? continentsSeen.map((c) => continentLabel(loc, c)).toList()
          : const [],
    );
  }

}
