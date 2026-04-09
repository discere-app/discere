import 'package:discere/model/language.dart';

import 'search_result.dart';

class TaxonomyDetail {
  final SearchResult result;
  final Map<Language, String?> commonNames;
  final List<TaxonomyClassificationEntry> classification;
  final List<TaxonomyMetric> metrics;
  final bool isReferenceBacked;

  const TaxonomyDetail({
    required this.result,
    required this.commonNames,
    required this.classification,
    required this.metrics,
    required this.isReferenceBacked,
  });
}

enum TaxonomyRankLabel { family, order, classType, superClass }

enum TaxonomyMetricType { species, genera, families, orders }

class TaxonomyClassificationEntry {
  final TaxonomyRankLabel label;
  final String scientificName;
  final String? commonName;

  const TaxonomyClassificationEntry({
    required this.label,
    required this.scientificName,
    this.commonName,
  });
}

class TaxonomyMetric {
  final TaxonomyMetricType type;
  final int count;

  const TaxonomyMetric({required this.type, required this.count});
}
