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
  final GlobalKey? imageKey;

  const FlashcardFront({
    required this.speciesWithLocalImages,
    this.watchlistKey,
    this.imageKey,
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

    final hasHints =
        species.maxLengthCm != null ||
        species.depthMinM != null ||
        species.depthMaxM != null;

    return Column(
      children: [
        // ── Image: the main attraction, gets all the space it can ─────────
        Expanded(
          child: FlashcardImageHeader(
            speciesWithLocalImages: speciesWithLocalImages,
            watchlistKey: watchlistKey,
            imageKey: imageKey,
          ),
        ),

        // ── Compact footer: tap hint + optional size/depth hints ──────────
        Padding(
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
