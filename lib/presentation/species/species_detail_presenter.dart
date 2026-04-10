import '../../model/biology/species.dart';
import '../../model/biology/species_native_region.dart';
import '../../model/language.dart';
import '../../model/ui/species_detail_view_data.dart';
import '../../model/ui/species_fact_view_data.dart';
import '../../model/ui/species_native_region_view_data.dart';
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

  SpeciesDetailViewData present(Species species, Language language) {
    return SpeciesDetailViewData(
      identity: _identityPresenter.present(species, language),
      isDeprecated: species.isDeprecated,
      classificationRows: _classificationPresenter.present(
        species.classification,
        language,
      ),
      facts: _buildFacts(species),
      habitatTags: species.traits.map(_humanizeTrait).toList(),
      nativeRegions: species.nativeRegions.map(_mapNativeRegion).toList(),
    );
  }

  List<SpeciesFactViewData> _buildFacts(Species species) {
    final facts = <SpeciesFactViewData>[];

    void addFact(SpeciesFactType type, String? value) {
      if (value == null || value.trim().isEmpty) return;
      facts.add(SpeciesFactViewData(type: type, value: value));
    }

    addFact(SpeciesFactType.size, species.size);
    addFact(SpeciesFactType.depth, species.depth);
    addFact(SpeciesFactType.habitat, species.habitat);
    addFact(SpeciesFactType.conservation, species.conservation);
    addFact(SpeciesFactType.bodyForm, species.bodyShape);
    addFact(SpeciesFactType.humanRisk, species.dangerousToHumans);
    addFact(SpeciesFactType.fishingImportance, species.fisheriesImportance);
    addFact(SpeciesFactType.typicalLifespan, species.longevityYears);
    addFact(SpeciesFactType.foodChainLevel, species.trophicLevelFood);

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
      isSubregion: region.scope == 'subregion',
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
