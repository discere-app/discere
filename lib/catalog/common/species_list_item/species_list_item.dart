import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_view_model.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class SpeciesListItem extends StatelessWidget {
  final SpeciesListItemViewModel item;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final String? deleteTooltip;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry? margin;

  const SpeciesListItem({
    super.key,
    required this.item,
    this.onTap,
    this.onDelete,
    this.deleteTooltip,
    this.leading,
    this.trailing,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin:
          margin ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
            vertical: AppSpacing.elementSpacing,
          ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: AppSpacing.cardPaddingAll,
          child: Row(
            children: [
              leading ??
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildLeadingImage(theme.colorScheme),
                  ),
              AppSpacing.widthS16,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.primaryName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    AppSpacing.heightS4,
                    Text(
                      item.scientificName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.additionalNames != null &&
                        item.additionalNames!.trim().isNotEmpty) ...[
                      AppSpacing.heightS4,
                      Text(
                        item.additionalNames!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: theme.colorScheme.error,
                  onPressed: onDelete,
                  tooltip: deleteTooltip,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingImage(ColorScheme colorScheme) {
    const width = 64.0;
    const height = 64.0;

    if (item.localImagePath != null && item.localImagePath!.isNotEmpty) {
      return Image.file(
        File(item.localImagePath!),
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    }

    if (item.remoteImageUrl != null && item.remoteImageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: item.remoteImageUrl!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        memCacheWidth: 128,
        memCacheHeight: 128,
        maxWidthDiskCache: 128,
        maxHeightDiskCache: 128,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, _) => _placeholder(colorScheme, width, height),
        errorWidget: (_, _, _) => _placeholder(colorScheme, width, height),
      );
    }

    return _placeholder(colorScheme, width, height);
  }

  Widget _placeholder(ColorScheme colorScheme, double width, double height) {
    return Container(
      width: width,
      height: height,
      color: colorScheme.secondaryContainer,
      child: Icon(
        Icons.image_not_supported_outlined,
        size: width * 0.45,
        color: colorScheme.onSecondaryContainer,
      ),
    );
  }
}
