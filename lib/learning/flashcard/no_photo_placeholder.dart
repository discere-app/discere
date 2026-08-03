import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shown in place of the image whenever a species has no local picture at
/// all — reached only once a deck's image-enrichment stages are complete
/// (see [DeckSessionPresenter.filterReviewableCards]), so this always means
/// no photo could be found, not just "not downloaded yet". Shared between
/// flip mode ([FlashcardFront]) and multiple-choice mode
/// ([FlashcardImageHeader]), which previously duplicated this block
/// identically.
class NoPhotoPlaceholder extends StatelessWidget {
  final String speciesId;
  final String speciesName;
  final GlobalKey? watchlistKey;
  final Future<void> Function(String speciesId)? onRemoveSpecies;

  const NoPhotoPlaceholder({
    required this.speciesId,
    required this.speciesName,
    this.watchlistKey,
    this.onRemoveSpecies,
    super.key,
  });

  Future<void> _confirmRemove(BuildContext context) async {
    final loc = context.loc;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('remove_species_confirm_dialog'),
        title: Text(loc.flashcardRemoveSpeciesConfirmTitle),
        content: Text(loc.flashcardRemoveSpeciesConfirmMessage(speciesName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.commonNo),
          ),
          TextButton(
            key: const Key('remove_species_confirm_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.commonYes),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await onRemoveSpecies?.call(speciesId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                context.loc.flashcardNoPhotoFoundHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              if (onRemoveSpecies != null) ...[
                AppSpacing.heightS8,
                TextButton(
                  key: const Key('remove_species_button'),
                  onPressed: () => _confirmRemove(context),
                  child: Text(context.loc.flashcardRemoveSpeciesButton),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          top: AppSpacing.s12,
          right: AppSpacing.s12,
          child: _buildWatchlistButton(
            context,
            theme,
            speciesId,
            buttonKey: watchlistKey,
          ),
        ),
      ],
    );
  }
}

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
