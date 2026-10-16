import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/shared/model/language.dart';

class TaxonomyDetail {
  final SearchResult result;
  final Map<Language, List<String>> commonNames;
  final List<TaxonomyClassificationEntry> classification;
  final List<TaxonomyMetric> metrics;
  final List<TaxonomyAttribute> attributes;
  final bool isReferenceBacked;

  /// Whether this taxon is a source's rank placeholder ("Not assigned"),
  /// which the reference database knows and a search result passed in may
  /// not.
  final bool isPlaceholder;

  const TaxonomyDetail({
    required this.result,
    required this.commonNames,
    required this.classification,
    required this.metrics,
    this.attributes = const [],
    required this.isReferenceBacked,
    this.isPlaceholder = false,
  });
}

enum TaxonomyRankLabel { family, order, classType, superClass }

enum TaxonomyMetricType { species, genera, families, orders }

class TaxonomyClassificationEntry {
  final TaxonomyRankLabel label;
  final String? id;
  final String scientificName;
  final Map<Language, List<String>> commonNames;

  /// A rank that assigns the taxon to no taxon above it: a source's rank
  /// placeholder ("Not assigned"), or a rank the chain does not reach, which
  /// has neither id nor name.
  final bool isUnassigned;

  const TaxonomyClassificationEntry({
    required this.label,
    this.id,
    required this.scientificName,
    this.commonNames = const {},
    this.isUnassigned = false,
  });
}

class TaxonomyMetric {
  final TaxonomyMetricType type;
  final int count;

  const TaxonomyMetric({required this.type, required this.count});
}

class TaxonomyAttribute {
  final String key;
  final String value;

  const TaxonomyAttribute({required this.key, required this.value});
}
