import 'package:discere/catalog/model/search_result.dart';
import 'package:material_ui/material_ui.dart';

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

  /// superClass has no dedicated [SearchEntityType] (it isn't a browsable
  /// search entity), so it isn't wired into [colorFor]/[iconFor] — callers
  /// reference these constants directly instead.
  static const Color superClassColor = Color(0xFF5AA0A8);
  static const IconData superClassIcon = Icons.workspaces_rounded;

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

  /// The rank's foreground color on a search result card, drawn from the
  /// theme — shared by the card's rank badge and its thumbnail placeholder.
  static Color accentFor(ColorScheme colorScheme, SearchEntityType entityType) {
    switch (entityType) {
      case SearchEntityType.species:
        return colorScheme.tertiary;
      case SearchEntityType.genus:
        return colorScheme.primary;
      case SearchEntityType.family:
        return colorScheme.secondary;
      case SearchEntityType.order:
        return colorScheme.onSurfaceVariant;
      case SearchEntityType.classType:
        return colorScheme.onSurface;
    }
  }

  /// The background [accentFor] sits on.
  static Color accentContainerFor(
    ColorScheme colorScheme,
    SearchEntityType entityType,
  ) {
    switch (entityType) {
      case SearchEntityType.species:
        return colorScheme.tertiaryContainer.withValues(alpha: 0.7);
      case SearchEntityType.genus:
        return colorScheme.primaryContainer.withValues(alpha: 0.7);
      case SearchEntityType.family:
        return colorScheme.secondaryContainer.withValues(alpha: 0.75);
      case SearchEntityType.order:
        return colorScheme.surfaceContainerHighest;
      case SearchEntityType.classType:
        return colorScheme.surfaceContainerHigh;
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
