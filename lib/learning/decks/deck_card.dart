import 'dart:io';

import 'package:discere/learning/decks/deck_enrichment_hint.dart';
import 'package:discere/learning/decks/learning_mode_style.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/view_deck.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
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
    if (oldWidget.deck.id != widget.deck.id) {
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
              // actually is a photo; decks without one get a small inline
              // placeholder in the header row instead of an empty band.
              if (hasCoverImage)
                Stack(
                  children: [
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
                        errorBuilder: (_, _, _) => Container(
                          color: colorScheme.secondary.withValues(alpha: 0.5),
                          child: const Center(
                            child: Icon(
                              Icons.image_not_supported,
                              size: 48,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.s8,
                      right: AppSpacing.s8,
                      child: _LearningModeBadge(
                        learningMode: deck.learningMode,
                        nameType: deck.nameType,
                      ),
                    ),
                  ],
                ),
              Padding(
                padding: AppSpacing.cardPaddingAll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!hasCoverImage) ...[
                          _CompactCoverPlaceholder(
                            learningMode: deck.learningMode,
                            nameType: deck.nameType,
                          ),
                          AppSpacing.widthS12,
                        ],
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
                              _StatSubtitle(deckStatFuture: _deckStatFuture),
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
                    _ActionButton(
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

/// Small badge shown over the cover image indicating whether the deck quizzes
/// on species or family identification.
class _LearningModeBadge extends StatelessWidget {
  static const _style = LearningModeStyle();

  final LearningMode learningMode;
  final NameType nameType;

  const _LearningModeBadge({required this.learningMode, required this.nameType});

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final modeLabel = _style.labelFor(learningMode, loc);
    final nameTypeLabel = _style.nameTypeLabelFor(nameType, loc);

    return Tooltip(
      message: loc.deckLearningModeTooltip('$modeLabel · $nameTypeLabel'),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _style.iconFor(learningMode),
          size: 16,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Small square placeholder shown inline in the header row (instead of the
/// full 16:9 cover band) for decks without a cover image, so a missing photo
/// doesn't reserve a photo's worth of vertical space in the list.
class _CompactCoverPlaceholder extends StatelessWidget {
  static const double _size = 56;

  final LearningMode learningMode;
  final NameType nameType;

  const _CompactCoverPlaceholder({
    required this.learningMode,
    required this.nameType,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              color: colorScheme.secondary.withValues(alpha: 0.5),
              child: const Center(
                child: Icon(
                  Icons.image_not_supported,
                  size: 24,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: _LearningModeBadge(
              learningMode: learningMode,
              nameType: nameType,
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtitle showing how many cards have been learned, loaded asynchronously.
class _StatSubtitle extends StatelessWidget {
  final Future<DeckStat> deckStatFuture;

  const _StatSubtitle({required this.deckStatFuture});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<DeckStat>(
      future: deckStatFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final stat = snapshot.data!;
        final learned = stat.totalCount - stat.uninitializedCount;
        return Text(
          context.loc.deckProgressSubtitle(learned, stat.totalCount),
          style: theme.textTheme.bodyMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

/// Start / Practice button shown at the bottom of the card.
class _ActionButton extends StatelessWidget {
  final ViewDeck deck;
  final VoidCallback onTap;
  final Future<DeckStat> deckStatFuture;

  const _ActionButton({
    required this.deck,
    required this.onTap,
    required this.deckStatFuture,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (deck.progress >= 1.0) {
      // All cards learned — offer a practice round
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.replay),
          label: Text(context.loc.commonPractice),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary.withValues(alpha: 0.2),
            foregroundColor: colorScheme.primary,
            elevation: 0,
            side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FutureBuilder<DeckStat>(
        future: deckStatFuture,
        builder: (context, snapshot) {
          final parts = <String>[];
          if (snapshot.hasData) {
            final stat = snapshot.data!;
            if (stat.dueCount > 0) {
              parts.add(context.loc.deckReviewButton(stat.dueCount));
            }
            if (stat.uninitializedCount > 0) {
              parts.add(
                context.loc.deckNewCardsButton(stat.uninitializedCount),
              );
            }
          }
          final label = parts.isNotEmpty
              ? parts.join('\n')
              : context.loc.commonPractice;
          return ElevatedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.play_arrow),
            label: Text(label, textAlign: TextAlign.center),
          );
        },
      ),
    );
  }
}
