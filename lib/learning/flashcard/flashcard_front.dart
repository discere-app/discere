import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/learning/flashcard/flashcard_image_header.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/util/depth_format.dart';
import 'package:discere/shared/util/length_format.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FlashcardFront extends StatelessWidget {
  final SpeciesWithLocalImages speciesWithLocalImages;
  final GlobalKey? watchlistKey;

  const FlashcardFront({
    required this.speciesWithLocalImages,
    this.watchlistKey,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final pictures = speciesWithLocalImages.localPictures;
    final species = speciesWithLocalImages.species;
    final theme = Theme.of(context);

    if (pictures.isEmpty) {
      return Stack(
        children: [
          Container(
            color: theme.colorScheme.surface,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.image_not_supported_outlined,
                  size: 48,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                AppSpacing.heightS12,
                Text(
                  context.loc.commonNoPictureAvailable,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: AppSpacing.s12,
            right: AppSpacing.s12,
            child: _buildWatchlistButton(
              context,
              theme,
              species.id,
              buttonKey: watchlistKey,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // ── Top: Image section ───────────────────────────────────────────
        Expanded(
          flex: 6,
          child: FlashcardImageHeader(
            speciesWithLocalImages: speciesWithLocalImages,
            watchlistKey: watchlistKey,
          ),
        ),

        // ── Bottom: Content section ──────────────────────────────────────
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.screenPadding,
              AppSpacing.s20,
              AppSpacing.s20,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Hint rows (Size / Depth — shown only when populated)
                Column(
                  children: [
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
                        padding: AppSpacing.buttonPaddingVertical,
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

Widget _buildWatchlistButton(
  BuildContext context,
  ThemeData theme,
  String speciesId, {
  GlobalKey? buttonKey,
}) {
  return Consumer<WatchlistService>(
    builder: (context, watchlistService, _) {
      final isWatchlisted = watchlistService.getSpecies().contains(speciesId);
      return IconButton(
        key: buttonKey,
        icon: Icon(
          isWatchlisted ? Icons.bookmark : Icons.bookmark_border,
          color: isWatchlisted
              ? Colors.amber.shade400
              : theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
        onPressed: () {
          if (isWatchlisted) {
            watchlistService.removeSpecies(speciesId);
          } else {
            watchlistService.addSpecies(speciesId);
          }
        },
      );
    },
  );
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
        AppSpacing.widthS12,
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
