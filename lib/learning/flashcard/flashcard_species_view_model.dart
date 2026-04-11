import 'package:discere/catalog/common/taxon_classification/classification_row_view_model.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_view_model.dart';

class FlashcardSpeciesViewModel {
  final TaxonIdentityViewModel identity;
  final List<ClassificationRowViewModel> classificationRows;

  const FlashcardSpeciesViewModel({
    required this.identity,
    required this.classificationRows,
  });
}
