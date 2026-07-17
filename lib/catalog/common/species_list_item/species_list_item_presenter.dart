import 'package:discere/catalog/common/species_list_item/species_list_item_view_model.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';

class SpeciesListItemPresenter {
  const SpeciesListItemPresenter();

  SpeciesListItemViewModel presentSpecies(Species species, Language language) {
    final localizedNames = resolveCommonNames(species.commonNames, language);

    return SpeciesListItemViewModel(
      primaryName: localizedNames.isNotEmpty
          ? localizedNames.first
          : species.getBinomialName(),
      scientificName: species.getBinomialName(),
      additionalNames: _additionalNames(localizedNames),
      localImagePath: null,
      remoteImageUrl: _remoteImageUrl(species),
    );
  }

  SpeciesListItemViewModel presentSpeciesWithLocalImages(
    SpeciesWithLocalImages speciesWithLocalImages,
    Language language,
  ) {
    final localizedNames = resolveCommonNames(
      speciesWithLocalImages.species.commonNames,
      language,
    );

    return SpeciesListItemViewModel(
      primaryName: localizedNames.isNotEmpty
          ? localizedNames.first
          : speciesWithLocalImages.species.getBinomialName(),
      scientificName: speciesWithLocalImages.species.getBinomialName(),
      additionalNames: _additionalNames(localizedNames),
      localImagePath: speciesWithLocalImages.localPictures.isEmpty
          ? null
          : speciesWithLocalImages.localPictures.first.localPath,
      remoteImageUrl: _remoteImageUrl(speciesWithLocalImages.species),
    );
  }

  SpeciesListItemViewModel presentSearchResult(
    SearchResult searchResult,
    Language language,
  ) {
    final localizedNames = resolveCommonNames(
      searchResult.commonNames,
      language,
    );

    return SpeciesListItemViewModel(
      primaryName: localizedNames.isNotEmpty
          ? localizedNames.first
          : searchResult.name.trim(),
      scientificName: searchResult.name.trim(),
      additionalNames: _additionalNames(localizedNames),
      localImagePath: null,
      remoteImageUrl: null,
    );
  }

  String? _remoteImageUrl(Species species) {
    if (species.pictures.isEmpty) return null;
    final url = species.pictures.first.url;
    if (url == null || url.isEmpty) return null;
    return url;
  }

  String? _additionalNames(List<String> localizedNames) {
    final additionalNames = localizedNames.skip(1).join(', ').trim();
    return additionalNames.isEmpty ? null : additionalNames;
  }
}
