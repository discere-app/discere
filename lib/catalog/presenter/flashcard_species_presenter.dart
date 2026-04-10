import 'package:discere/catalog/model/species.dart';
import 'package:discere/shared/model/language.dart';
import '../view_data/flashcard_species_view_data.dart';
import 'species_classification_presenter.dart';
import 'species_identity_presenter.dart';

class FlashcardSpeciesPresenter {
  final SpeciesIdentityPresenter _identityPresenter;
  final SpeciesClassificationPresenter _classificationPresenter;

  const FlashcardSpeciesPresenter({
    SpeciesIdentityPresenter identityPresenter =
        const SpeciesIdentityPresenter(),
    SpeciesClassificationPresenter classificationPresenter =
        const SpeciesClassificationPresenter(),
  }) : _identityPresenter = identityPresenter,
       _classificationPresenter = classificationPresenter;

  FlashcardSpeciesViewData present(Species species, Language language) {
    return FlashcardSpeciesViewData(
      identity: _identityPresenter.present(species, language),
      classificationRows: _classificationPresenter.present(
        species.classification,
        language,
      ),
    );
  }
}
