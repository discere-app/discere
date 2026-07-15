import 'package:discere/catalog/common/taxon_classification/taxon_classification_presenter.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_view_model.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';

import 'package:discere/learning/flashcard/flashcard_species_view_model.dart';

class FlashcardSpeciesPresenter {
  final TaxonClassificationPresenter _classificationPresenter;

  const FlashcardSpeciesPresenter({
    TaxonClassificationPresenter classificationPresenter =
        const TaxonClassificationPresenter(),
  }) : _classificationPresenter = classificationPresenter;

  FlashcardSpeciesViewModel present(
    Species species,
    Language language, {
    LearningMode learningMode = LearningMode.species,
    NameType nameType = NameType.commonName,
  }) {
    final scientificName = switch (learningMode) {
      LearningMode.species => species.getBinomialName(),
      LearningMode.genus => species.classification.genusScientificName,
      LearningMode.family => species.classification.familyScientificName,
    };
    final commonNames = resolveCommonNames(
      switch (learningMode) {
        LearningMode.species => species.commonNames,
        LearningMode.genus => species.classification.genusCommonNames,
        LearningMode.family => species.classification.familyCommonNames,
      },
      language,
    );

    return FlashcardSpeciesViewModel(
      identity: _buildIdentity(scientificName, commonNames, nameType),
      classificationRows: _classificationPresenter.present(species, language),
    );
  }

  TaxonIdentityViewModel _buildIdentity(
    String scientificName,
    List<String> commonNames,
    NameType nameType,
  ) {
    final primaryName = switch (nameType) {
      NameType.scientificName => scientificName,
      NameType.commonName =>
        commonNames.isNotEmpty ? commonNames.first : scientificName,
    };

    return TaxonIdentityViewModel(
      primaryName: primaryName,
      scientificName: scientificName,
      commonNames: commonNames,
    );
  }
}
