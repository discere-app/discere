import 'package:discere/catalog/model/species.dart';
import 'package:discere/shared/model/language.dart';
import '../view_data/species_identity_view_data.dart';
import 'package:discere/shared/util/common_name_utils.dart';

class SpeciesIdentityPresenter {
  const SpeciesIdentityPresenter();

  SpeciesIdentityViewData present(Species species, Language language) {
    final scientificName = species.getBinomialName();
    final commonNames = _resolveCommonNames(species, language);

    return SpeciesIdentityViewData(
      primaryName: commonNames.isNotEmpty ? commonNames.first : scientificName,
      scientificName: scientificName,
      commonNames: commonNames,
    );
  }

  List<String> _resolveCommonNames(Species species, Language language) {
    final rawNames =
        species.commonNames[language] ?? species.commonNames[Language.en];
    return splitCommonNames(rawNames);
  }
}
