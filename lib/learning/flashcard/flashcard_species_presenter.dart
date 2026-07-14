import 'package:discere/catalog/common/taxon_classification/taxon_classification_presenter.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_presenter.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_view_model.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';

import 'package:discere/learning/flashcard/flashcard_species_view_model.dart';

class FlashcardSpeciesPresenter {
  final TaxonIdentityPresenter _identityPresenter;
  final TaxonClassificationPresenter _classificationPresenter;

  const FlashcardSpeciesPresenter({
    TaxonIdentityPresenter identityPresenter = const TaxonIdentityPresenter(),
    TaxonClassificationPresenter classificationPresenter =
        const TaxonClassificationPresenter(),
  }) : _identityPresenter = identityPresenter,
       _classificationPresenter = classificationPresenter;

  FlashcardSpeciesViewModel present(
    Species species,
    Language language, {
    LearningMode learningMode = LearningMode.species,
  }) {
    return FlashcardSpeciesViewModel(
      identity: switch (learningMode) {
        LearningMode.species => _identityPresenter.present(species, language),
        LearningMode.family => _presentFamily(species, language),
      },
      classificationRows: _classificationPresenter.present(
        species.classification,
        language,
      ),
    );
  }

  TaxonIdentityViewModel _presentFamily(Species species, Language language) {
    final classification = species.classification;
    final scientificName = classification.familyScientificName;
    final commonNames = resolveCommonNames(
      classification.familyCommonNames,
      language,
    );

    return TaxonIdentityViewModel(
      primaryName: commonNames.isNotEmpty ? commonNames.first : scientificName,
      scientificName: scientificName,
      commonNames: commonNames,
    );
  }
}
