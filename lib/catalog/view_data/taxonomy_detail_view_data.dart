class TaxonomyDetailViewData {
  final String pageTitle;
  final String entityLabel;
  final String primaryTitle;
  final String scientificName;
  final List<String> commonNames;
  final List<TaxonomyMetricViewData> metrics;
  final List<TaxonomyClassificationRowViewData> classificationRows;
  final List<TaxonomyAttributeViewData> attributes;
  final bool isReferenceBacked;
  final String emptyCommonNamesLabel;
  final String emptyClassificationLabel;
  final String referenceHint;
  final String attributesTitle;

  const TaxonomyDetailViewData({
    required this.pageTitle,
    required this.entityLabel,
    required this.primaryTitle,
    required this.scientificName,
    required this.commonNames,
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

class TaxonomyMetricViewData {
  final String label;
  final int count;

  const TaxonomyMetricViewData({required this.label, required this.count});
}

class TaxonomyClassificationRowViewData {
  final String label;
  final String scientificName;
  final String? commonName;

  const TaxonomyClassificationRowViewData({
    required this.label,
    required this.scientificName,
    this.commonName,
  });
}

class TaxonomyAttributeViewData {
  final String label;
  final String value;

  const TaxonomyAttributeViewData({required this.label, required this.value});
}
