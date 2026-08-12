import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/learning/flashcard/flashcard_image_header.dart';
import 'package:discere/learning/flashcard/flip_swipe_detector.dart';
import 'package:discere/learning/flashcard/no_photo_placeholder.dart';
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

  /// Flips the card, optionally with a swipe direction that determines
  /// which way it visually rotates (see [FlashcardWidgetState._flip]).
  /// Applied via [FlipSwipeDetector] to everything here EXCEPT the image
  /// itself — the image is a tap target for fullscreen and a swipe target
  /// for its own photo carousel (see [FlashcardImageHeader]), so it can't
  /// also flip on tap/swipe without conflicting with either. The image
  /// still flips on long-press, as a fallback for the rare case where
  /// nothing else on this card is tappable (landscape front with no
  /// size/depth hints to show).
  final void Function({FlipDirection? direction}) onFlip;

  const FlashcardFront({
    required this.speciesWithLocalImages,
    required this.onFlip,
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
        onTap: onFlip,
        onSwipe: (direction) => onFlip(direction: direction),
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
          onLongPress: onFlip,
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
            onTap: onFlip,
            onSwipe: (direction) => onFlip(direction: direction),
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
                      _HintRow(
                        label: context.loc.speciesSize,
                        value: formatLengthCm(species.maxLengthCm!)!,
                        theme: theme,
                        stacked: true,
                        muted: false,
                      ),
                      AppSpacing.heightS16,
                    ],
                    if (species.depthMinM != null || species.depthMaxM != null)
                      _HintRow(
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
            onLongPress: onFlip,
            child: FlashcardImageHeader(
              speciesWithLocalImages: speciesWithLocalImages,
              watchlistKey: watchlistKey,
              imageKey: imageKey,
            ),
          ),
        ),

        // ── Compact footer: tap hint + optional size/depth hints ──────────
        FlipSwipeDetector(
          onTap: onFlip,
          onSwipe: (direction) => onFlip(direction: direction),
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
                const _TapToRevealHint(),
                if (hasHints) ...[
                  AppSpacing.heightS12,
                  if (species.maxLengthCm != null) ...[
                    _HintRow(
                      label: context.loc.speciesSize,
                      value: formatLengthCm(species.maxLengthCm!)!,
                      theme: theme,
                    ),
                    AppSpacing.heightS8,
                  ],
                  if (species.depthMinM != null || species.depthMaxM != null)
                    _HintRow(
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
class _TapToRevealHint extends StatefulWidget {
  const _TapToRevealHint();

  @override
  State<_TapToRevealHint> createState() => _TapToRevealHintState();
}

class _TapToRevealHintState extends State<_TapToRevealHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final Animation<double> _pulse = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  ).drive(Tween(begin: 0.35, end: 1.0));

  bool _hasStartedAnimating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasStartedAnimating) return;
    _hasStartedAnimating = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1.0;
    } else {
      _runPulses();
    }
  }

  /// A handful of pulses to catch the eye on first appearance, then settles
  /// on full opacity — deliberately finite (not `repeat()`) so it doesn't
  /// keep `pumpAndSettle()` spinning forever in widget tests.
  Future<void> _runPulses() async {
    for (var i = 0; i < 3 && mounted; i++) {
      await _controller.forward();
      if (i < 2 && mounted) await _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _pulse,
          child: Icon(
            Icons.visibility_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
        ),
        AppSpacing.widthS8,
        Text(
          context.loc.flashcardTapToReveal,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _HintRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;

  /// Label above value instead of side-by-side — used in the narrow
  /// landscape hints column, where there isn't room for the portrait
  /// Row layout's fixed-width label column.
  final bool stacked;

  /// Portrait dims this to a quiet secondary note below the image. Landscape
  /// has nothing else in its hints column competing for attention, so it
  /// uses full contrast instead of reading as a disabled/low-priority label.
  final bool muted;

  const _HintRow({
    required this.label,
    required this.value,
    required this.theme,
    this.stacked = false,
    this.muted = true,
  });

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label.toUpperCase(),
      style: theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
        color: theme.colorScheme.onSurface.withValues(alpha: muted ? 0.4 : 0.6),
      ),
    );
    final valueText = Text(
      value,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: muted ? null : 14,
        color: muted
            ? theme.colorScheme.onSurface.withValues(alpha: 0.85)
            : theme.colorScheme.primary,
      ),
    );

    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [labelText, AppSpacing.heightS4, valueText],
      );
    }

    return Row(
      children: [
        SizedBox(width: 80, child: labelText),
        AppSpacing.widthS12,
        Expanded(child: valueText),
      ],
    );
  }
}
