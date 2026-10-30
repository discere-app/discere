import 'dart:io';

import 'package:discere/learning/decks/deck_enrichment_hint.dart';
import 'package:discere/learning/decks/deck_replacement_hint.dart';
import 'package:discere/learning/decks/deck_update_hint.dart';
import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/learning/decks/widgets/action_button.dart';
import 'package:discere/learning/decks/widgets/deck_progress_row.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/image_placeholder.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class DeckCard extends StatelessWidget {
  final DeckViewModel deck;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDismiss;
  final GlobalKey? favoriteKey;
  final GlobalKey? editKey;
  final GlobalKey? shareKey;

  const DeckCard({
    super.key,
    required this.deck,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onTap,
    required this.onEdit,
    required this.onShare,
    required this.onDismiss,
    this.favoriteKey,
    this.editKey,
    this.shareKey,
  });

  @override
  Widget build(BuildContext context) {
    final stored = deck.stored;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasCoverImage = stored.coverImagePath != null;

    return Dismissible(
      key: Key(stored.id!),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.s20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDismiss(),
      confirmDismiss: (_) => _showDeleteConfirmationDialog(context),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cover image — only reserves the full 16:9 band when there
              // actually is a photo; decks without one skip it entirely
              // rather than showing an empty placeholder.
              if (hasCoverImage)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.file(
                    File(stored.coverImagePath!),
                    fit: BoxFit.cover,
                    // Cover images are user-selected camera photos and
                    // can be far higher resolution than the card
                    // renders at; cap the decode to the card's
                    // on-screen size instead of decoding full-res.
                    cacheWidth:
                        (MediaQuery.sizeOf(context).width *
                                MediaQuery.devicePixelRatioOf(context))
                            .round(),
                    errorBuilder: (context, _, _) => ImagePlaceholder(
                      icon: Icons.image_not_supported,
                      label: context.loc.commonNoPictureAvailable,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              Padding(
                padding: AppSpacing.cardPaddingAll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            stored.name,
                            style: theme.textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: favoriteKey,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: isFavorite
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                              onPressed: onFavoriteToggle,
                            ),
                            IconButton(
                              key: editKey,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.edit_square,
                                color: colorScheme.onSurface,
                              ),
                              onPressed: onEdit,
                            ),
                            IconButton(
                              key: shareKey,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.share,
                                color: colorScheme.onSurface,
                              ),
                              onPressed: onShare,
                            ),
                          ],
                        ),
                      ],
                    ),
                    DeckUpdateHint(deckId: stored.id!),
                    DeckReplacementHint(deckId: stored.id!),
                    DeckEnrichmentHint(deckId: stored.id!),
                    AppSpacing.heightS16,
                    DeckProgressRow(deck: deck),
                    AppSpacing.heightS16,
                    // Action button
                    ActionButton(deck: deck, onTap: onTap),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showDeleteConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.loc.deleteDeckConfirmationTitle),
          content: Text(context.loc.deleteDeckConfirmationMessage),
          actions: [
            TextButton(
              key: const Key('delete_deck_cancel_button'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.loc.commonCancel),
            ),
            TextButton(
              key: const Key('delete_deck_confirm_button'),
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(context.loc.deleteDeckConfirmButton),
            ),
          ],
        );
      },
    );
  }
}
