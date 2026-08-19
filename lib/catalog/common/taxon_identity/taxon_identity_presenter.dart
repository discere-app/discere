import 'package:discere/catalog/common/taxon_identity/taxon_identity_view_model.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';

class TaxonIdentityPresenter {
  const TaxonIdentityPresenter();

  TaxonIdentityViewModel present(Species species, Language language) {
    final scientificName = species.getBinomialName();
    final resolution = resolveCommonNamesResolution(
      species.commonNames,
      language,
    );

    return TaxonIdentityViewModel(
      primaryName: resolution.names.isNotEmpty
          ? resolution.names.first
          : scientificName,
      scientificName: scientificName,
      commonNames: resolution.names,
      isEnglishFallback: resolution.isEnglishFallback,
    );
  }
}
