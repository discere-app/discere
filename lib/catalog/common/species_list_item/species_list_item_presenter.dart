import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_view_model.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';

class SpeciesListItemPresenter {
  const SpeciesListItemPresenter();

  SpeciesListItemViewModel presentSpecies(Species species, Language language) {
    return SpeciesListItemViewModel(
      primaryName: _primaryName(species, language),
      scientificName: species.getBinomialName(),
      additionalNames: null,
      localImagePath: null,
      remoteImageUrl: _remoteImageUrl(species),
    );
  }

  SpeciesListItemViewModel presentSpeciesWithLocalImages(
    SpeciesWithLocalImages speciesWithLocalImages,
    Language language,
  ) {
    return SpeciesListItemViewModel(
      primaryName: _primaryName(speciesWithLocalImages.species, language),
      scientificName: speciesWithLocalImages.species.getBinomialName(),
      additionalNames: null,
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
    final localizedNames = _localizedCommonNames(searchResult, language);

    return SpeciesListItemViewModel(
      primaryName: localizedNames.isNotEmpty
          ? localizedNames.first
          : searchResult.name.trim(),
      scientificName: searchResult.name.trim(),
      additionalNames: localizedNames.skip(1).join(', ').trim().isEmpty
          ? null
          : localizedNames.skip(1).join(', '),
      localImagePath: null,
      remoteImageUrl: null,
    );
  }

  String _primaryName(Species species, Language language) {
    return species.commonNames[language] ??
        species.commonNames[Language.en] ??
        species.getBinomialName();
  }

  String? _remoteImageUrl(Species species) {
    if (species.pictures.isEmpty) return null;
    final url = species.pictures.first.url;
    if (url == null || url.isEmpty) return null;
    return url;
  }

  List<String> _localizedCommonNames(
    SearchResult searchResult,
    Language language,
  ) {
    final preferredNames = splitCommonNames(searchResult.commonNames[language]);
    if (preferredNames.isNotEmpty) return preferredNames;

    if (language != Language.en) {
      final englishNames = splitCommonNames(
        searchResult.commonNames[Language.en],
      );
      if (englishNames.isNotEmpty) return englishNames;
    }

    return const [];
  }
}
