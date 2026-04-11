import 'package:flutter/material.dart';

import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_result_card.dart';
import 'package:discere/shared/extensions/localization_extension.dart';

/// Compact card used for genus, family, order, and class search results.
///
/// These entries stay text-first so mixed search result lists remain fast to
/// scan even when species cards contain richer media.
class TaxonomySearchResultCard extends StatelessWidget {
  final String primaryName;
  final String scientificName;
  final String? additionalNames;
  final SearchEntityType entityType;
  final VoidCallback onTap;

  const TaxonomySearchResultCard({
    super.key,
    required this.primaryName,
    required this.scientificName,
    required this.additionalNames,
    required this.entityType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SearchResultCard(
      primaryName: primaryName,
      scientificName: scientificName,
      additionalNames: additionalNames,
      entityTypeLabel: _entityTypeLabel(context),
      entityType: entityType,
      onTap: onTap,
    );
  }

  String _entityTypeLabel(BuildContext context) {
    switch (entityType) {
      case SearchEntityType.species:
        return context.loc.classificationSpecies;
      case SearchEntityType.genus:
        return context.loc.classificationGenus;
      case SearchEntityType.family:
        return context.loc.classificationFamily;
      case SearchEntityType.order:
        return context.loc.classificationOrder;
      case SearchEntityType.classType:
        return context.loc.classificationClass;
    }
  }
}
