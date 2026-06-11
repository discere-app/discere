import 'package:discere/catalog/model/search_result.dart';

class TaxonomyClassificationRowViewModel {
  final String label;
  final String? id;
  final SearchEntityType? entityType;
  final String scientificName;
  final String? commonName;

  const TaxonomyClassificationRowViewModel({
    required this.label,
    this.id,
    this.entityType,
    required this.scientificName,
    this.commonName,
  });
}
