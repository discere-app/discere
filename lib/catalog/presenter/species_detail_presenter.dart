import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_native_region.dart';
import '../../l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
import '../view_data/species_detail_view_data.dart';
import '../view_data/species_fact_view_data.dart';
import '../view_data/species_native_region_view_data.dart';
import 'species_classification_presenter.dart';
import 'species_identity_presenter.dart';

class SpeciesDetailPresenter {
  final SpeciesIdentityPresenter _identityPresenter;
  final SpeciesClassificationPresenter _classificationPresenter;

  const SpeciesDetailPresenter({
    SpeciesIdentityPresenter identityPresenter =
        const SpeciesIdentityPresenter(),
    SpeciesClassificationPresenter classificationPresenter =
        const SpeciesClassificationPresenter(),
  }) : _identityPresenter = identityPresenter,
       _classificationPresenter = classificationPresenter;

  SpeciesDetailViewData present(
    Species species,
    Language language,
    AppLocalizations loc,
  ) {
    final nativeRegions = species.nativeRegions.map(_mapNativeRegion).toList();

    return SpeciesDetailViewData(
      identity: _identityPresenter.present(species, language),
      isDeprecated: species.isDeprecated,
      classificationRows: _classificationPresenter.present(
        species.classification,
        language,
      ),
      factsSection: SpeciesFactsSectionViewData(
        title: loc.speciesDetailFactsTitle,
        habitatTitle: 'Habitat',
        facts: _buildFacts(species, loc),
        habitatTags: species.traits.map(_humanizeTrait).toList(),
      ),
      nativeRegionsSection: nativeRegions.isEmpty
          ? null
          : SpeciesNativeRegionsSectionViewData(
              title: 'Native regions',
              subtitle: 'Selected native records from the reference data.',
              moreLabelSuffix: 'more native regions',
              nativeRegions: nativeRegions,
            ),
    );
  }

  List<SpeciesFactViewData> _buildFacts(
    Species species,
    AppLocalizations loc,
  ) {
    final facts = <SpeciesFactViewData>[];

    void addFact(SpeciesFactType type, String label, String? value) {
      if (value == null || value.trim().isEmpty) return;
      facts.add(SpeciesFactViewData(type: type, label: label, value: value));
    }

    addFact(SpeciesFactType.size, loc.speciesSize, species.size);
    addFact(SpeciesFactType.depth, loc.speciesDepth, species.depth);
    addFact(
      SpeciesFactType.habitat,
      loc.speciesDetailHabitat,
      species.habitat,
    );
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

  SpeciesNativeRegionViewData _mapNativeRegion(SpeciesNativeRegion region) {
    return SpeciesNativeRegionViewData(
      badgeLabel: region.scope == 'subregion' ? 'Subregion' : 'Country',
      label: region.label,
      secondary: _buildNativeRegionSecondary(region),
    );
  }

  String? _buildNativeRegionSecondary(SpeciesNativeRegion region) {
    final parts = <String>[
      if (region.establishmentStatus != null) region.establishmentStatus!,
      if (region.presenceStatus != null) region.presenceStatus!,
      if (region.isThreatened) 'threatened',
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }
}
