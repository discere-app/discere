import 'dart:io';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class SpeciesMediaCarousel extends StatefulWidget {
  final SpeciesWithLocalImages speciesWithLocalImages;
  final double height;
  final BorderRadius borderRadius;

  const SpeciesMediaCarousel({
    super.key,
    required this.speciesWithLocalImages,
    required this.height,
    required this.borderRadius,
  });

  @override
  State<SpeciesMediaCarousel> createState() => _SpeciesMediaCarouselState();
}

class _SpeciesMediaCarouselState extends State<SpeciesMediaCarousel> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();
    final theme = Theme.of(context);

    if (items.isEmpty) {
      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: widget.borderRadius,
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

    final hasMultiple = items.length > 1;

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Container(color: Colors.black),
            CarouselSlider.builder(
              itemCount: items.length,
              options: CarouselOptions(
                height: widget.height,
                viewportFraction: 1,
                enlargeCenterPage: false,
                enableInfiniteScroll: hasMultiple,
                onPageChanged: (index, _) {
                  if (hasMultiple) {
                    setState(() => _currentIndex = index);
                  }
                },
              ),
              itemBuilder: (context, index, realIndex) {
                final item = items[index];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _CarouselImage(item: item),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.s8,
                          AppSpacing.s8,
                          AppSpacing.s8,
                          AppSpacing.s24,
                        ),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black54, Colors.transparent],
                          ),
                        ),
                        alignment: Alignment.topRight,
                        child: Text(
                          item.picture.attributionText,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 8,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (hasMultiple)
              Positioned(
                bottom: AppSpacing.s12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    items.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s4,
                      ),
                      width: index == _currentIndex ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: index == _currentIndex
                            ? theme.colorScheme.primary
                            : Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_SpeciesCarouselItem> _buildItems() {
    final localPathByUrl = <String, String>{
      for (final localPicture in widget.speciesWithLocalImages.localPictures)
        if (localPicture.picture.url != null)
          localPicture.picture.url!: localPicture.localPath,
    };

    final items = <_SpeciesCarouselItem>[];
    final seen = <String>{};

    for (final picture in widget.speciesWithLocalImages.species.pictures) {
      final url = picture.url;
      if (url == null || url.isEmpty) continue;
      if (!seen.add(url)) continue;

      items.add(
        _SpeciesCarouselItem(
          picture: picture,
          localPath: localPathByUrl[url],
          remoteUrl: url,
        ),
      );
    }

    return items;
  }
}

class _CarouselImage extends StatelessWidget {
  final _SpeciesCarouselItem item;

  const _CarouselImage({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.localPath != null) {
      return Image.file(File(item.localPath!), fit: BoxFit.contain);
    }

    return Image.network(
      item.remoteUrl,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return const _ImageFallback();
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const _ImageFallback(showLoader: true);
      },
    );
  }
}

class _ImageFallback extends StatelessWidget {
  final bool showLoader;

  const _ImageFallback({this.showLoader = false});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black),
        Center(
          child: Icon(
            Icons.image_outlined,
            size: 34,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
        if (showLoader)
          const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }
}

class _SpeciesCarouselItem {
  final Picture picture;
  final String? localPath;
  final String remoteUrl;

  const _SpeciesCarouselItem({
    required this.picture,
    required this.localPath,
    required this.remoteUrl,
  });
}
