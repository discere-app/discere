import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/learning/flashcard/flashcard_image_header.dart';
import 'package:discere/learning/flashcard/flip_swipe_detector.dart';
import 'package:discere/learning/flashcard/no_photo_placeholder.dart';
import 'package:discere/learning/flashcard/widgets/hint_row.dart';
import 'package:discere/learning/flashcard/widgets/tap_to_reveal_hint.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/util/depth_format.dart';
import 'package:discere/shared/util/length_format.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class FlashcardFront extends StatelessWidget {
  final SpeciesWithLocalImages speciesWithLocalImages;
  final GlobalKey? watchlistKey;
  final GlobalKey? imageKey;
  final Future<void> Function(String speciesId)? onRemoveSpecies;

  /// Drives tap/drag-to-flip. Applied via [FlipSwipeDetector] to everything
  /// here EXCEPT the image itself — the image is a tap target for
  /// fullscreen and a drag target for its own photo carousel (see
  /// [FlashcardImageHeader]), so it can't also flip on tap/drag without
  /// conflicting with either. The image still flips on long-press, as a
  /// fallback for the rare case where nothing else on this card is
  /// tappable (landscape front with no size/depth hints to show).
  final FlashcardFlipController flipController;

  const FlashcardFront({
    required this.speciesWithLocalImages,
    required this.flipController,
    this.watchlistKey,
    this.imageKey,
    this.onRemoveSpecies,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final pictures = speciesWithLocalImages.localPictures;
    final species = speciesWithLocalImages.species;
    final theme = Theme.of(context);

    if (pictures.isEmpty) {
      return FlipSwipeDetector(
        controller: flipController,
        child: NoPhotoPlaceholder(
          speciesId: species.id,
          speciesName: species.scientificName,
          watchlistKey: watchlistKey,
          onRemoveSpecies: onRemoveSpecies,
        ),
      );
    }

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final hasHints =
        species.maxLengthCm != null ||
        species.depthMinM != null ||
        species.depthMaxM != null;

    // Landscape moves the hints beside the image instead of below it — the
    // rating buttons already moved into a side rail (see DeckPage), so the
    // image can take the rest of the card, and the portrait footer's
    // fade-to-background gradient (FlashcardImageHeader's
    // showBottomGradient) has nothing left below it to blend into. The
    // "tap to reveal" hint is dropped here rather than reflowed — the whole
    // card is already tappable, and it read as clutter competing with the
    // actual size/depth info for the one thing worth showing in a narrow
    // column. No hints column at all when there's no size/depth data to
    // show — the image gets the width instead of an empty sidebar.
    if (isLandscape) {
      final image = Expanded(
        child: GestureDetector(
          onLongPress: flipController.onTap,
          child: FlashcardImageHeader(
            speciesWithLocalImages: speciesWithLocalImages,
            watchlistKey: watchlistKey,
            imageKey: imageKey,
            showBottomGradient: false,
          ),
        ),
      );
      if (!hasHints) return Row(children: [image]);

      return Row(
        children: [
          // Gradient into black at the image edge rather than a flat fill —
          // avoids a hard seam where this column meets the image's own
          // black letterbox backdrop, while still reading as an on-theme
          // (not pure-black) surface further from the image.
          FlipSwipeDetector(
            controller: flipController,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [theme.scaffoldBackgroundColor, Colors.black],
                ),
              ),
              width: 130,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (species.maxLengthCm != null) ...[
                      HintRow(
                        label: context.loc.speciesSize,
                        value: formatLengthCm(species.maxLengthCm!)!,
                        theme: theme,
                        stacked: true,
                        muted: false,
                      ),
                      AppSpacing.heightS16,
                    ],
                    if (species.depthMinM != null || species.depthMaxM != null)
                      HintRow(
                        label: context.loc.speciesDepth,
                        value: formatDepthRangeM(
                          species.depthMinM,
                          species.depthMaxM,
                        )!,
                        theme: theme,
                        stacked: true,
                        muted: false,
                      ),
                  ],
                ),
              ),
            ),
          ),
          image,
        ],
      );
    }

    return Column(
      children: [
        // ── Image: the main attraction, gets all the space it can ─────────
        Expanded(
          child: GestureDetector(
            onLongPress: flipController.onTap,
            child: FlashcardImageHeader(
              speciesWithLocalImages: speciesWithLocalImages,
              watchlistKey: watchlistKey,
              imageKey: imageKey,
            ),
          ),
        ),

        // ── Compact footer: tap hint + optional size/depth hints ──────────
        FlipSwipeDetector(
          controller: flipController,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.s12,
              AppSpacing.s20,
              AppSpacing.s16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TapToRevealHint(),
                if (hasHints) ...[
                  AppSpacing.heightS12,
                  if (species.maxLengthCm != null) ...[
                    HintRow(
                      label: context.loc.speciesSize,
                      value: formatLengthCm(species.maxLengthCm!)!,
                      theme: theme,
                    ),
                    AppSpacing.heightS8,
                  ],
                  if (species.depthMinM != null || species.depthMaxM != null)
                    HintRow(
                      label: context.loc.speciesDepth,
                      value: formatDepthRangeM(
                        species.depthMinM,
                        species.depthMaxM,
                      )!,
                      theme: theme,
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

/// Replaces the old full-width "tap to reveal" button with a quiet
/// affordance: the entire card is already tappable (see [FlashcardWidget]'s
/// GestureDetector), this just signals it without competing with the image
/// for space or attention.