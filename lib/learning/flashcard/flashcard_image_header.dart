import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/learning/flashcard/no_photo_placeholder.dart';
import 'package:discere/learning/flashcard/watchlist_button.dart';
import 'package:discere/shared/model/carousel_image.dart';
import 'package:discere/shared/ui/image_carousel.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                  // The review flow keeps orientation unlocked for its whole
                  // session (see DeckPage), so closing the fullscreen viewer
                  // must restore "all orientations", not the app-wide
                  // portrait-only default — otherwise it snaps the still-open
                  // deck page back to portrait and blocks rotation.
                  restoreOrientationsOnFullscreenClose:
                      DeviceOrientation.values,
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
              child: WatchlistButton(
                speciesId: species.id,
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
