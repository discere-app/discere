import 'package:discere/catalog/taxonomy_detail/taxonomy_attribute_view_model.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_classification_row_view_model.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_metric_view_model.dart';

class TaxonomyDetailViewModel {
  final String pageTitle;
  final String entityLabel;
  final String primaryTitle;
  final String scientificName;
  final List<String> commonNames;

  /// Whether [primaryTitle]/[commonNames] are an English fallback because
  /// the requested language had no common name for this taxon.
  final bool isEnglishFallback;
  final List<TaxonomyMetricViewModel> metrics;
  final List<TaxonomyClassificationRowViewModel> classificationRows;
  final List<TaxonomyAttributeViewModel> attributes;
  final bool isReferenceBacked;
  final String emptyCommonNamesLabel;
  final String emptyClassificationLabel;
  final String referenceHint;
  final String attributesTitle;

  const TaxonomyDetailViewModel({
    required this.pageTitle,
    required this.entityLabel,
    required this.primaryTitle,
    required this.scientificName,
    required this.commonNames,
    required this.isEnglishFallback,
    required this.metrics,
    required this.classificationRows,
    required this.attributes,
    required this.isReferenceBacked,
    required this.emptyCommonNamesLabel,
    required this.emptyClassificationLabel,
    required this.referenceHint,
    required this.attributesTitle,
  });
}
