import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/search/search_result_card.dart';
import 'package:discere/catalog/search/search_result_thumbnail.dart';
import 'package:discere/catalog/search/search_result_thumbnail_placeholder.dart';
import 'package:discere/catalog/taxonomy_detail/search_taxonomy_style.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:material_ui/material_ui.dart';

/// Compact card used for genus, family, order, and class rows.
///
/// Like a species row it leads with a picture of the taxon; the badge names
/// the rank, and the picture's placeholder takes the rank's colors.
class TaxonomySearchResultCard extends StatelessWidget {
  static const double _thumbnailSize = 64;

  final String primaryName;
  final String scientificName;
  final String? additionalNames;
  final SearchEntityType entityType;

  /// Looks the picture up by the taxon's name key ([TaxonRank.entityKey] of
  /// [scientificName]), the key its iNaturalist id is kept under. Null for
  /// a source's rank placeholder, which is no taxon to look a picture up
  /// for and shows the placeholder alone.
  final Future<String?> Function(String entityKey)? resolveThumbnailUrl;
  final VoidCallback onTap;

  const TaxonomySearchResultCard({
    super.key,
    required this.primaryName,
    required this.scientificName,
    required this.additionalNames,
    required this.entityType,
    required this.resolveThumbnailUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SearchResultCard(
      leading: _leading(Theme.of(context).colorScheme),
      primaryName: primaryName,
      scientificName: scientificName,
      additionalNames: additionalNames,
      entityTypeLabel: _entityTypeLabel(context),
      entityType: entityType,
      onTap: onTap,
    );
  }

  Widget _leading(ColorScheme colorScheme) {
    final accent = SearchTaxonomyStyle.accentFor(colorScheme, entityType);
    final accentContainer = SearchTaxonomyStyle.accentContainerFor(
      colorScheme,
      entityType,
    );
    final borderRadius = BorderRadius.circular(8);
    final resolveThumbnailUrl = this.resolveThumbnailUrl;

    if (resolveThumbnailUrl == null) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: SizedBox.square(
          dimension: _thumbnailSize,
          child: SearchResultThumbnailPlaceholder(
            backgroundColor: accentContainer,
            accentColor: accent,
          ),
        ),
      );
    }
    return SearchResultThumbnail(
      thumbnailKey: TaxonRank.fromSearchEntityType(
        entityType,
      ).entityKey(scientificName),
      resolveThumbnailUrl: resolveThumbnailUrl,
      size: _thumbnailSize,
      accentColor: accent,
      backgroundColor: accentContainer,
      borderRadius: borderRadius,
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
