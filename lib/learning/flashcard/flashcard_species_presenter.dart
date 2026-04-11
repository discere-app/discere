import 'package:discere/catalog/common/taxon_classification/taxon_classification_presenter.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_presenter.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/shared/model/language.dart';

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

  FlashcardSpeciesViewModel present(Species species, Language language) {
    return FlashcardSpeciesViewModel(
      identity: _identityPresenter.present(species, language),
      classificationRows: _classificationPresenter.present(
        species.classification,
        language,
      ),
    );
  }
}
