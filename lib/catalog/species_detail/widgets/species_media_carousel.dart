import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/carousel_image.dart';
import 'package:discere/shared/ui/image_carousel.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class SpeciesMediaCarousel extends StatelessWidget {
  final SpeciesWithLocalImages speciesWithLocalImages;
  final double height;
  final BorderRadius borderRadius;

  const SpeciesMediaCarousel({
    super.key,
    required this.speciesWithLocalImages,
    required this.height,
    required this.borderRadius,
  });

  List<CarouselImage> _buildItems() {
    final localPathByUrl = <String, String>{
      for (final localPicture in speciesWithLocalImages.localPictures)
        if (localPicture.picture.url != null)
          localPicture.picture.url!: localPicture.localPath,
    };

    final items = <CarouselImage>[];
    final seen = <String>{};

    for (final picture in speciesWithLocalImages.species.pictures) {
      final url = picture.url;
      if (url == null || url.isEmpty) continue;
      if (!seen.add(url)) continue;

      items.add(
        CarouselImage(
          localPath: localPathByUrl[url],
          remoteUrl: url,
          attributionText: picture.attributionText,
        ),
      );
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _buildItems();

    if (items.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: borderRadius,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_not_supported_outlined,
                size: 42,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
              const SizedBox(height: AppSpacing.s12),
              Text(
                context.loc.commonNoPictureAvailable,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ImageCarousel(
              pictures: items,
              constraints: constraints,
              enableFullscreenOnTap: true,
              enableFullscreenOnLongPress: false,
            );
          },
        ),
      ),
    );
  }
}
