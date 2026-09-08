import 'dart:io';

import 'package:discere/learning/decks/deck_enrichment_hint.dart';
import 'package:discere/learning/decks/deck_update_hint.dart';
import 'package:discere/learning/decks/view_deck.dart';
import 'package:discere/learning/decks/widgets/action_button.dart';
import 'package:discere/learning/decks/widgets/stat_subtitle.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/image_placeholder.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:discere/theme/ocean_theme/ocean_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DeckCard extends StatefulWidget {
  final ViewDeck deck;
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
  State<DeckCard> createState() => _DeckCardState();
}

class _DeckCardState extends State<DeckCard> {
  late Future<DeckStat> _deckStatFuture;

  @override
  void initState() {
    super.initState();
    _deckStatFuture = _fetchDeckStat();
  }

  @override
  void didUpdateWidget(covariant DeckCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Identity, not just id: DecksView passes the exact same ViewDeck
    // instance on incidental rebuilds (e.g. a different deck's favorite
    // toggling), but a genuine reload — like returning from a review
    // session — always supplies a freshly fetched ViewDeck, even for a
    // deck whose id didn't change. Refetch precisely on the latter.
    if (oldWidget.deck != widget.deck) {
      _deckStatFuture = _fetchDeckStat();
    }
  }

  Future<DeckStat> _fetchDeckStat() {
    return Provider.of<FlashcardService>(
      context,
      listen: false,
    ).getDeckStat(widget.deck.id!);
  }

  @override
  Widget build(BuildContext context) {
    final deck = widget.deck;
    final isFavorite = widget.isFavorite;
    final onFavoriteToggle = widget.onFavoriteToggle;
    final onTap = widget.onTap;
    final onEdit = widget.onEdit;
    final onShare = widget.onShare;
    final onDismiss = widget.onDismiss;
    final favoriteKey = widget.favoriteKey;
    final editKey = widget.editKey;
    final shareKey = widget.shareKey;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasCoverImage = deck.coverImagePath != null;

    return Dismissible(
      key: Key(deck.id!),
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
                    File(deck.coverImagePath!),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                deck.name,
                                style: theme.textTheme.titleLarge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              AppSpacing.heightS4,
                              StatSubtitle(deckStatFuture: _deckStatFuture),
                            ],
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
                    DeckUpdateHint(deckId: deck.id!),
                    DeckEnrichmentHint(deckId: deck.id!),
                    AppSpacing.heightS16,
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: deck.progress,
                        minHeight: 6,
                        backgroundColor: colorScheme.onSurface.withValues(
                          alpha: 0.1,
                        ),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          deck.progress >= 1.0
                              ? OceanColors.success
                              : colorScheme.primary,
                        ),
                      ),
                    ),
                    AppSpacing.heightS16,
                    // Action button
                    ActionButton(
                      deck: deck,
                      onTap: onTap,
                      deckStatFuture: _deckStatFuture,
                    ),
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

/// Icons for whichever of learning mode / name type / review mode deviate
/// from the deck defaults (species / common name / flip), stacked vertically
/// at the trailing edge of the deck's start/practice button content, using
/// the button's own foreground color (dimmed) so they read as part of the
/// button rather than a separate element next to it. Placed inside the
/// button rather than on the cover image or next to the title because it's
/// the one spot on the card that exists unconditionally, regardless of
/// whether the deck has a cover image. Non-default settings are the
/// exception, not the rule, so decks left on defaults show no icons at all.
/// Subtitle showing how many cards have been learned, loaded asynchronously.
/// Start-review button shown at the bottom of the card. Disabled when
/// neither due reviews nor new cards are currently available — the deck's
/// overall progress doesn't factor in here, only what the FSRS scheduler
/// says is ready right now.
/// Lays out an action button's icon + label + trailing mode-icon column in
/// one row, so the mode icons render as part of the button's own content
/// (inheriting its foreground color) instead of a separately styled sibling.