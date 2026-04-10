import 'classification_row_view_data.dart';
import 'species_identity_view_data.dart';

class FlashcardSpeciesViewData {
  final SpeciesIdentityViewData identity;
  final List<ClassificationRowViewData> classificationRows;

  const FlashcardSpeciesViewData({
    required this.identity,
    required this.classificationRows,
  });
}
