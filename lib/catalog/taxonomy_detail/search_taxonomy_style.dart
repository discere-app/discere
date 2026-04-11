import 'package:flutter/material.dart';

import 'package:discere/catalog/model/search_result.dart';

/// Central visual style tokens for taxonomy-aware search result cards.
///
/// Keeping colors and icons together makes the rank styling easy to reuse and
/// easy to tune without touching individual widgets.
class SearchTaxonomyStyle {
  SearchTaxonomyStyle._();

  static const Color speciesColor = Color(0xFFC96A54);
  static const Color genusColor = Color(0xFFD08A3C);
  static const Color familyColor = Color(0xFFC4A64A);
  static const Color orderColor = Color(0xFF6F9A6D);
  static const Color classColor = Color(0xFF5E8E96);

  static Color colorFor(SearchEntityType entityType) {
    switch (entityType) {
      case SearchEntityType.species:
        return speciesColor;
      case SearchEntityType.genus:
        return genusColor;
      case SearchEntityType.family:
        return familyColor;
      case SearchEntityType.order:
        return orderColor;
      case SearchEntityType.classType:
        return classColor;
    }
  }

  static IconData iconFor(SearchEntityType entityType) {
    switch (entityType) {
      case SearchEntityType.species:
        return Icons.pets;
      case SearchEntityType.genus:
        return Icons.account_tree_rounded;
      case SearchEntityType.family:
        return Icons.device_hub_rounded;
      case SearchEntityType.order:
        return Icons.linear_scale_rounded;
      case SearchEntityType.classType:
        return Icons.grid_view_rounded;
    }
  }
}
