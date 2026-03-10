import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/biology/species_with_local_images.dart';
import '../../service/common/watchlist_service.dart';
import 'image_carousel.dart';

class FlashCardFront extends StatelessWidget {
  final SpeciesWithLocalImages speciesWithLocalImages;

  const FlashCardFront({
    required this.speciesWithLocalImages,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final images = speciesWithLocalImages.localImages;
    final species = speciesWithLocalImages.species;
    final theme = Theme.of(context);

    if (images.isEmpty) {
      return Container(
        color: theme.colorScheme.surface,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: 48,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              context.loc.commonNoPictureAvailable,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ── Top: Image section ───────────────────────────────────────────
        Expanded(
          flex: 6,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  // Image carousel
                  Positioned.fill(
                    child: ImageCarousel(
                      key: const Key('image'),
                      images: images,
                      constraints: constraints,
                    ),
                  ),

                  // Bottom gradient fade into card surface
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 80,
                    child: IgnorePointer(
                      child: Container(
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
                  ),

                  // Watchlist button — top right, glass effect
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Consumer<WatchListService>(
                      builder: (context, watchListService, _) {
                        final isWatchlisted =
                            watchListService.getSpecies().contains(species.id);
                        return _GlassButton(
                          child: IconButton(
                            icon: Icon(
                              isWatchlisted
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              color: isWatchlisted
                                  ? Colors.amber.shade400
                                  : Colors.white.withValues(alpha: 0.85),
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
                ],
              );
            },
          ),
        ),

        // ── Bottom: Content section ──────────────────────────────────────
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Hint rows (Size / Depth — shown only when populated)
                Column(
                  children: [
                    if (species.size != null && species.size!.isNotEmpty) ...[
                      _HintRow(
                        label: context.loc.speciesSize,
                        value: species.size!,
                        theme: theme,
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (species.depth != null && species.depth!.isNotEmpty)
                      _HintRow(
                        label: context.loc.speciesDepth,
                        value: species.depth!,
                        theme: theme,
                      ),
                  ],
                ),

                // "Tap to reveal" button — full width, primary style
                IgnorePointer(
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(context.loc.flashcardTapToReveal),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

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

class _HintRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;

  const _HintRow({
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label.toUpperCase(),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}
