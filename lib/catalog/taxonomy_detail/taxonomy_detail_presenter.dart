import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_attribute_view_model.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_classification_row_view_model.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_view_model.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_metric_view_model.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';

class TaxonomyDetailPresenter {
  const TaxonomyDetailPresenter();

  /// The AppBar title, available before the full [TaxonomyDetail] has
  /// loaded — it only depends on the entity type, which the search result
  /// already carries.
  String pageTitleFor(SearchEntityType type, AppLocalizations loc) =>
      _entityLabel(loc, type);

  TaxonomyDetailViewModel present(
    TaxonomyDetail detail,
    Language language,
    AppLocalizations loc,
  ) {
    final resolution = resolveCommonNamesResolution(
      detail.commonNames,
      language,
    );

    return TaxonomyDetailViewModel(
      pageTitle: _entityLabel(loc, detail.result.type),
      entityLabel: _entityLabel(loc, detail.result.type),
      primaryTitle: resolution.names.isNotEmpty
          ? resolution.names.first
          : detail.result.name,
      scientificName: detail.result.name,
      commonNames: resolution.names,
      isEnglishFallback: resolution.isEnglishFallback,
      metrics: detail.metrics
          .map(
            (metric) => TaxonomyMetricViewModel(
              label: _metricLabel(loc, metric.type),
              count: metric.count,
            ),
          )
          .toList(),
      classificationRows: detail.classification
          .map(
            (entry) => TaxonomyClassificationRowViewModel(
              label: _classificationLabel(loc, entry.label),
              id: entry.id,
              entityType: _entityTypeForRankLabel(entry.label),
              scientificName: entry.scientificName,
              commonName: entry.commonName,
            ),
          )
          .where((entry) => entry.scientificName.isNotEmpty)
          .toList(),
      attributes: detail.attributes
          .map(
            (attribute) => TaxonomyAttributeViewModel(
              label: _attributeLabel(attribute.key),
              value: attribute.value,
            ),
          )
          .toList(),
      isReferenceBacked: detail.isReferenceBacked,
      emptyCommonNamesLabel: loc.commonNotAvailable,
      emptyClassificationLabel: detail.isReferenceBacked
          ? loc.commonNoData
          : loc.searchDetailReferenceHint,
      referenceHint: loc.searchDetailReferenceHint,
      attributesTitle: 'Attributes',
    );
  }

  String _entityLabel(AppLocalizations loc, SearchEntityType type) {
    switch (type) {
      case SearchEntityType.genus:
        return loc.classificationGenus;
      case SearchEntityType.family:
        return loc.classificationFamily;
      case SearchEntityType.order:
        return loc.classificationOrder;
      case SearchEntityType.classType:
        return loc.classificationClass;
      case SearchEntityType.species:
        return loc.classificationSpecies;
    }
  }

  SearchEntityType? _entityTypeForRankLabel(TaxonomyRankLabel label) {
    switch (label) {
      case TaxonomyRankLabel.family:
        return SearchEntityType.family;
      case TaxonomyRankLabel.order:
        return SearchEntityType.order;
      case TaxonomyRankLabel.classType:
        return SearchEntityType.classType;
      case TaxonomyRankLabel.superClass:
        return null;
    }
  }

  String _classificationLabel(AppLocalizations loc, TaxonomyRankLabel label) {
    switch (label) {
      case TaxonomyRankLabel.family:
        return loc.classificationFamily;
      case TaxonomyRankLabel.order:
        return loc.classificationOrder;
      case TaxonomyRankLabel.classType:
        return loc.classificationClass;
      case TaxonomyRankLabel.superClass:
        return loc.classificationSuperClass;
    }
  }

  String _metricLabel(AppLocalizations loc, TaxonomyMetricType type) {
    switch (type) {
      case TaxonomyMetricType.species:
        return loc.searchDetailContainedSpecies;
      case TaxonomyMetricType.genera:
        return loc.searchDetailContainedGenera;
      case TaxonomyMetricType.families:
        return loc.searchDetailContainedFamilies;
      case TaxonomyMetricType.orders:
        return loc.searchDetailContainedOrders;
    }
  }

  String _attributeLabel(String key) {
    return key
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }
}
