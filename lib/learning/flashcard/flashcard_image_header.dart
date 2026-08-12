import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/learning/flashcard/no_photo_placeholder.dart';
import 'package:discere/shared/model/carousel_image.dart';
import 'package:discere/shared/ui/image_carousel.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The image carousel + watchlist button shown at the top of a flashcard,
/// shared between flip mode ([FlashcardFront]) and multiple-choice mode
/// ([FlashcardMultipleChoiceFront]). Sized to fill whatever space its parent
/// (typically an `Expanded`) gives it; callers own the surrounding layout and
/// their own fallback for the "no pictures at all" case where that differs.
class FlashcardImageHeader extends StatelessWidget {
  final SpeciesWithLocalImages speciesWithLocalImages;
  final GlobalKey? watchlistKey;
  final GlobalKey? imageKey;
  final Future<void> Function(String speciesId)? onRemoveSpecies;

  /// Fades the bottom of the carousel into the surrounding card surface —
  /// meant to blend the image into a footer rendered below it (see
  /// [FlashcardFront]'s hint footer). Callers with nothing below the image
  /// (the landscape flip front) turn this off so the image reads as clean
  /// full-bleed content instead of fading into the background for no reason.
  final bool showBottomGradient;

  const FlashcardImageHeader({
    required this.speciesWithLocalImages,
    this.watchlistKey,
    this.imageKey,
    this.onRemoveSpecies,
    this.showBottomGradient = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final pictures = speciesWithLocalImages.localPictures;
    final species = speciesWithLocalImages.species;
    final theme = Theme.of(context);

    if (pictures.isEmpty) {
      return NoPhotoPlaceholder(
        speciesId: species.id,
        speciesName: species.scientificName,
        watchlistKey: watchlistKey,
        onRemoveSpecies: onRemoveSpecies,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Image carousel
            Positioned.fill(
              child: KeyedSubtree(
                key: imageKey,
                child: ImageCarousel(
                  key: const Key('image'),
                  pictures: pictures
                      .map(
                        (p) => CarouselImage(
                          localPath: p.localPath,
                          attributionText: p.picture.attributionText,
                        ),
                      )
                      .toList(),
                  constraints: constraints,
                  enableFullscreenOnTap: true,
                  enableFullscreenOnLongPress: false,
                  // Fade into the card surface without washing out the dot
                  // indicators, which render above this overlay.
                  foregroundOverlay: showBottomGradient
                      ? IgnorePointer(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    (theme.cardTheme.color ?? theme.cardColor),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ),

            // Watchlist button — top right, glass effect
            Positioned(
              top: AppSpacing.s12,
              right: AppSpacing.s12,
              child: _buildWatchlistButton(
                context,
                theme,
                species.id,
                glass: true,
                buttonKey: watchlistKey,
              ),
            ),
          ],
        );
      },
    );
  }
}

Widget _buildWatchlistButton(
  BuildContext context,
  ThemeData theme,
  String speciesId, {
  bool glass = false,
  GlobalKey? buttonKey,
}) {
  return Consumer<WatchlistService>(
    builder: (context, watchlistService, _) {
      final isWatchlisted = watchlistService.getSpecies().contains(speciesId);
      final icon = IconButton(
        key: buttonKey,
        icon: Icon(
          isWatchlisted ? Icons.bookmark : Icons.bookmark_border,
          color: isWatchlisted
              ? Colors.amber.shade400
              : (glass
                    ? Colors.white.withValues(alpha: 0.85)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
        onPressed: () {
          if (isWatchlisted) {
            watchlistService.removeSpecies(speciesId);
          } else {
            watchlistService.addSpecies(speciesId);
          }
        },
      );
      return glass ? _GlassButton(child: icon) : icon;
    },
  );
}

class _GlassButton extends StatelessWidget {
  final Widget child;

  const _GlassButton({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }
}
