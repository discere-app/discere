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

/// Icons for whichever of learning mode / name type / review mode deviate
/// from the deck defaults (species / common name / flip), stacked vertically
/// at the trailing edge of the deck's start/practice button content, using
/// the button's own foreground color (dimmed) so they read as part of the
/// button rather than a separate element next to it. Placed inside the
/// button rather than on the cover image or next to the title because it's
/// the one spot on the card that exists unconditionally, regardless of
/// whether the deck has a cover image. Non-default settings are the
/// exception, not the rule, so decks left on defaults show no icons at all.
class _LearningModeIconColumn extends StatelessWidget {
  static const _style = LearningModeStyle();
  static const double _iconSize = 14;

  final LearningMode learningMode;
  final NameType nameType;
  final ReviewMode reviewMode;

  const _LearningModeIconColumn({
    required this.learningMode,
    required this.nameType,
    required this.reviewMode,
  });

  static bool hasNonDefault({
    required LearningMode learningMode,
    required NameType nameType,
    required ReviewMode reviewMode,
  }) =>
      learningMode != LearningMode.species ||
      nameType != NameType.commonName ||
      reviewMode != ReviewMode.flip;

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final color = (IconTheme.of(context).color ?? Theme.of(context).colorScheme.onPrimary)
        .withValues(alpha: 0.7);

    Widget iconWithTooltip(IconData icon, String tooltip) {
      return Tooltip(
        message: tooltip,
        child: Icon(icon, size: _iconSize, color: color),
      );
    }

    final icons = [
      if (learningMode != LearningMode.species)
        iconWithTooltip(
          _style.iconFor(learningMode),
          _style.labelFor(learningMode, loc),
        ),
      if (nameType != NameType.commonName)
        iconWithTooltip(
          _style.nameTypeIconFor(nameType),
          _style.nameTypeLabelFor(nameType, loc),
        ),
      if (reviewMode != ReviewMode.flip)
        iconWithTooltip(
          _style.reviewModeIconFor(reviewMode),
          _style.reviewModeLabelFor(reviewMode, loc),
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < icons.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          icons[i],
        ],
      ],
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
    final modeIcons = _LearningModeIconColumn.hasNonDefault(
          learningMode: deck.learningMode,
          nameType: deck.nameType,
          reviewMode: deck.reviewMode,
        )
        ? _LearningModeIconColumn(
            learningMode: deck.learningMode,
            nameType: deck.nameType,
            reviewMode: deck.reviewMode,
          )
        : null;

    if (deck.progress >= 1.0) {
      // All cards learned — offer a practice round
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary.withValues(alpha: 0.2),
            foregroundColor: colorScheme.primary,
            elevation: 0,
            side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
          ),
          child: _ButtonContent(
            icon: Icons.replay,
            label: context.loc.commonPractice,
            modeIcons: modeIcons,
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
          return ElevatedButton(
            onPressed: onTap,
            child: _ButtonContent(
              icon: Icons.play_arrow,
              label: label,
              modeIcons: modeIcons,
            ),
          );
        },
      ),
    );
  }
}

/// Lays out an action button's icon + label + trailing mode-icon column in
/// one row, so the mode icons render as part of the button's own content
/// (inheriting its foreground color) instead of a separately styled sibling.
class _ButtonContent extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? modeIcons;

  const _ButtonContent({
    required this.icon,
    required this.label,
    required this.modeIcons,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        AppSpacing.widthS8,
        Expanded(child: Text(label, textAlign: TextAlign.center)),
        if (modeIcons != null) ...[AppSpacing.widthS8, modeIcons!],
      ],
    );
  }
}
