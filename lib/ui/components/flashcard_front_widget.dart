import 'dart:io';

import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../../model/biology/species_with_local_images.dart';
import '../../service/common/watchlist_service.dart';
import 'image_carousel.dart';

class FlashCardFront extends StatefulWidget {
  final SpeciesWithLocalImages speciesWithLocalImages;

  const FlashCardFront({
    required this.speciesWithLocalImages,
    super.key,
  });

  @override
  FlashCardFrontState createState() => FlashCardFrontState();
}

class FlashCardFrontState extends State<FlashCardFront> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final images = widget.speciesWithLocalImages.localImages;
        final species = widget.speciesWithLocalImages.species;
        final theme = Theme.of(context);
        
        if (images.isEmpty) {
          return Container(
            color: theme.colorScheme.surface,
            alignment: Alignment.center,
            child: Text(context.loc.commonNoPictureAvailable),
          );
        }
        
        return Stack(
          fit: StackFit.expand,
          children: [
            // Carousel Hero Images
            Positioned.fill(
              child: ImageCarousel(
                key: const Key('image'),
                images: images,
                constraints: constraints,
              ),
            ),
            // Deep Gradient Overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 160,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Theme.of(context).colorScheme.surface,
                        Theme.of(context).colorScheme.surface.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Context Tag (Habitat/Classification hint)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.water_drop, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      species.classification.classScientificName.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Watchlist Button
            Positioned(
              top: 16,
              right: 16,
              child: Consumer<WatchListService>(
                builder: (context, watchListService, child) {
                  final isWatchlisted = watchListService.getSpecies().contains(species.id);
                  return Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withOpacity(0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: IconButton(
                      icon: Icon(
                        isWatchlisted ? Icons.bookmark : Icons.bookmark_border,
                        color: isWatchlisted ? Colors.yellow.shade400 : Colors.white.withOpacity(0.8),
                      ),
                      onPressed: () {
                        if (isWatchlisted) {
                          watchListService.removeSpecies(species.id);
                        } else {
                          watchListService.addSpecies(species.id);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            // Tap to flip UI hint
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Tap to reveal',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
