import '../../l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import '../view_data/taxonomy_detail_view_data.dart';
import 'package:discere/shared/util/common_name_utils.dart';

class TaxonomyDetailPresenter {
  const TaxonomyDetailPresenter();

  TaxonomyDetailViewData present(
    TaxonomyDetail detail,
    Language language,
    AppLocalizations loc,
  ) {
    final commonNames = _commonNames(detail, language);

    return TaxonomyDetailViewData(
      pageTitle: _entityLabel(loc, detail.result.type),
      entityLabel: _entityLabel(loc, detail.result.type),
      primaryTitle: commonNames.isNotEmpty ? commonNames.first : detail.result.name,
      scientificName: detail.result.name,
      commonNames: commonNames,
      metrics: detail.metrics
          .map(
            (metric) => TaxonomyMetricViewData(
              label: _metricLabel(loc, metric.type),
              count: metric.count,
            ),
          )
          .toList(),
      classificationRows: detail.classification
          .map(
            (entry) => TaxonomyClassificationRowViewData(
              label: _classificationLabel(loc, entry.label),
              scientificName: entry.scientificName,
              commonName: entry.commonName,
            ),
          )
          .where((entry) => entry.scientificName.isNotEmpty)
          .toList(),
      attributes: detail.attributes
          .map(
            (attribute) => TaxonomyAttributeViewData(
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

  List<String> _commonNames(TaxonomyDetail detail, Language language) {
    final localized = splitCommonNames(detail.commonNames[language]);
    if (localized.isNotEmpty) return localized;

    if (language != Language.en) {
      final english = splitCommonNames(detail.commonNames[Language.en]);
      if (english.isNotEmpty) return english;
    }

    return const [];
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
