import 'package:discere/catalog/model/search_result.dart';

class TaxonomyClassificationRowViewModel {
  final String label;
  final String? id;
  final SearchEntityType? entityType;
  final String scientificName;
  final String? commonName;

  /// Shown as unassigned rather than under [scientificName]: a source's rank
  /// placeholder ("Not assigned"), still navigable by [id], or a rank the
  /// chain does not reach, which has no id.
  final bool isUnassigned;

  const TaxonomyClassificationRowViewModel({
    required this.label,
    this.id,
    this.entityType,
    required this.scientificName,
    this.commonName,
    this.isUnassigned = false,
  });
}
