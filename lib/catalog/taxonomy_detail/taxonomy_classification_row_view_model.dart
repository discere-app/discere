import 'package:discere/catalog/model/search_result.dart';

class TaxonomyClassificationRowViewModel {
  final String label;
  final String? id;
  final SearchEntityType? entityType;
  final String scientificName;
  final String? commonName;

  /// A source's rank placeholder ("Not assigned"): shown as unassigned rather
  /// than under [scientificName], still navigable by [id].
  final bool isPlaceholder;

  const TaxonomyClassificationRowViewModel({
    required this.label,
    this.id,
    this.entityType,
    required this.scientificName,
    this.commonName,
    this.isPlaceholder = false,
  });
}
