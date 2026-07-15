import 'dart:io';

import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/learning/decks/learning_mode_style.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/theme/ocean_theme/ocean_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:discere/learning/model/view_deck.dart';
import '../../theme/app_spacing.dart';
import '../../learning/service/flashcard_service.dart';
import '../../enrichment/service/inat_enrichment_queue_service.dart';

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
              // Cover image
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: deck.coverImagePath != null
                        ? Image.file(
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
                              color: colorScheme.secondary.withValues(
                                alpha: 0.5,
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  size: 48,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            color: colorScheme.secondary.withValues(
                              alpha: 0.5,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.image_not_supported,
                                size: 48,
                                color: Colors.white54,
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
                              icon: Icon(
                                Icons.edit_square,
                                color: colorScheme.onSurface,
                              ),
                              onPressed: onEdit,
                            ),
                            IconButton(
                              key: shareKey,
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
                    _EnrichmentHint(deckId: deck.id!),
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

class _EnrichmentHint extends StatelessWidget {
  final String deckId;

  const _EnrichmentHint({required this.deckId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Selector<INatEnrichmentQueueService, DeckEnrichmentInfo>(
      selector: (context, service) => service.deckInfo(deckId),
      builder: (context, info, child) {
        if (info.state == DeckEnrichmentState.hidden) {
          if (info.lastCompletedAt == null && info.lastAttemptedAt == null) {
            return const SizedBox.shrink();
          }
        }

        final hint = _hintFor(context, info);
        if (hint == null) return const SizedBox.shrink();

        return InkWell(
          onTap: () => _showStateExplainDialog(context, info.state),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(hint.icon, size: 14, color: hint.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hint.text,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: hint.color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.info_outline,
                  size: 12,
                  color: hint.color.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showStateExplainDialog(
    BuildContext context,
    DeckEnrichmentState current,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final loc = dialogContext.loc;
        return AlertDialog(
          title: Text(loc.inatDeckStateExplainTitle),
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final state in _explainedStatesInOrder)
                  _StateExplainRow(
                    state: state,
                    isCurrent: state == current,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(loc.commonOk),
            ),
          ],
        );
      },
    );
  }

  static const List<DeckEnrichmentState> _explainedStatesInOrder = [
    DeckEnrichmentState.pending,
    DeckEnrichmentState.loadingBase,
    DeckEnrichmentState.loadingExtended,
    DeckEnrichmentState.done,
    DeckEnrichmentState.doneWithGaps,
    DeckEnrichmentState.cooldown,
    DeckEnrichmentState.paused,
    DeckEnrichmentState.failed,
  ];

  _DeckHintVisual? _hintFor(
    BuildContext context,
    DeckEnrichmentInfo info,
  ) {
    final loc = context.loc;
    final icon = _iconForState(info.state);
    final color = _colorForState(info.state);
    switch (info.state) {
      case DeckEnrichmentState.hidden:
        if (info.lastCompletedAt != null) {
          return _DeckHintVisual(
            text: _formatLastCompleted(context, info.lastCompletedAt!),
            icon: Icons.check_circle_outline,
            color: color,
          );
        }
        return null;
      case DeckEnrichmentState.loadingBase:
        return _DeckHintVisual(
          text: info.progressTotal > 0
              ? loc.inatDeckStateLoadingBaseProgress(
                  info.progressCompleted,
                  info.progressTotal,
                )
              : loc.inatDeckStateLoadingBase,
          icon: icon,
          color: color,
        );
      case DeckEnrichmentState.loadingExtended:
        return _DeckHintVisual(
          text: info.progressTotal > 0
              ? loc.inatDeckStateLoadingExtendedProgress(
                  info.progressCompleted,
                  info.progressTotal,
                )
              : loc.inatDeckStateLoadingExtended,
          icon: icon,
          color: color,
        );
      case DeckEnrichmentState.done:
        return _DeckHintVisual(
          text: info.lastCompletedAt != null
              ? _formatLastCompleted(context, info.lastCompletedAt!)
              : loc.inatDeckStateDone,
          icon: icon,
          color: color,
        );
      case DeckEnrichmentState.pending:
      case DeckEnrichmentState.doneWithGaps:
      case DeckEnrichmentState.cooldown:
      case DeckEnrichmentState.paused:
      case DeckEnrichmentState.failed:
        return _DeckHintVisual(
          text: _labelForState(loc, info.state),
          icon: icon,
          color: color,
        );
    }
  }

  static IconData _iconForState(DeckEnrichmentState state) {
    switch (state) {
      case DeckEnrichmentState.hidden:
        return Icons.check_circle_outline;
      case DeckEnrichmentState.pending:
        return Icons.hourglass_top_outlined;
      case DeckEnrichmentState.loadingBase:
        return Icons.cloud_download_outlined;
      case DeckEnrichmentState.loadingExtended:
        return Icons.cloud_sync_outlined;
      case DeckEnrichmentState.done:
        return Icons.check_circle;
      case DeckEnrichmentState.doneWithGaps:
        return Icons.check_circle_outline;
      case DeckEnrichmentState.cooldown:
        return Icons.cloud_off_outlined;
      case DeckEnrichmentState.paused:
        return Icons.pause_circle_outline;
      case DeckEnrichmentState.failed:
        return Icons.error_outline;
    }
  }

  static Color _colorForState(DeckEnrichmentState state) {
    switch (state) {
      case DeckEnrichmentState.hidden:
      case DeckEnrichmentState.pending:
      case DeckEnrichmentState.cooldown:
      case DeckEnrichmentState.paused:
        return OceanColors.primaryTextDark;
      case DeckEnrichmentState.loadingBase:
        return OceanColors.primaryBlue;
      case DeckEnrichmentState.loadingExtended:
      case DeckEnrichmentState.done:
      case DeckEnrichmentState.doneWithGaps:
        return OceanColors.success;
      case DeckEnrichmentState.failed:
        return OceanColors.error;
    }
  }

  static String _labelForState(
    AppLocalizations loc,
    DeckEnrichmentState state,
  ) {
    switch (state) {
      case DeckEnrichmentState.hidden:
      case DeckEnrichmentState.pending:
        return loc.inatDeckStatePending;
      case DeckEnrichmentState.loadingBase:
        return loc.inatDeckStateLoadingBase;
      case DeckEnrichmentState.loadingExtended:
        return loc.inatDeckStateLoadingExtended;
      case DeckEnrichmentState.done:
        return loc.inatDeckStateDone;
      case DeckEnrichmentState.doneWithGaps:
        return loc.inatDeckStateDoneWithGaps;
      case DeckEnrichmentState.cooldown:
        return loc.inatDeckStateCooldown;
      case DeckEnrichmentState.paused:
        return loc.inatDeckStatePaused;
      case DeckEnrichmentState.failed:
        return loc.inatDeckStateFailed;
    }
  }

  static String _descriptionForState(
    AppLocalizations loc,
    DeckEnrichmentState state,
  ) {
    switch (state) {
      case DeckEnrichmentState.hidden:
      case DeckEnrichmentState.pending:
        return loc.inatDeckStateDescPending;
      case DeckEnrichmentState.loadingBase:
        return loc.inatDeckStateDescLoadingBase;
      case DeckEnrichmentState.loadingExtended:
        return loc.inatDeckStateDescLoadingExtended;
      case DeckEnrichmentState.done:
        return loc.inatDeckStateDescDone;
      case DeckEnrichmentState.doneWithGaps:
        return loc.inatDeckStateDescDoneWithGaps;
      case DeckEnrichmentState.cooldown:
        return loc.inatDeckStateDescCooldown;
      case DeckEnrichmentState.paused:
        return loc.inatDeckStateDescPaused;
      case DeckEnrichmentState.failed:
        return loc.inatDeckStateDescFailed;
    }
  }

  String _formatLastCompleted(BuildContext context, DateTime completedAt) {
    final difference = DateTime.now().difference(completedAt);
    if (difference.inMinutes < 1) {
      return context.loc.inatDeckStatusUpdatedNow;
    }
    if (difference.inHours < 1) {
      return context.loc.inatDeckStatusUpdatedMinutes(difference.inMinutes);
    }
    if (difference.inDays < 1) {
      return context.loc.inatDeckStatusUpdatedHours(difference.inHours);
    }
    return context.loc.inatDeckStatusUpdatedDays(difference.inDays);
  }

}

class _DeckHintVisual {
  final String text;
  final IconData icon;
  final Color color;

  const _DeckHintVisual({
    required this.text,
    required this.icon,
    required this.color,
  });
}

class _StateExplainRow extends StatelessWidget {
  final DeckEnrichmentState state;
  final bool isCurrent;

  const _StateExplainRow({required this.state, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final theme = Theme.of(context);
    final icon = _EnrichmentHint._iconForState(state);
    final color = _EnrichmentHint._colorForState(state);
    final label = _EnrichmentHint._labelForState(loc, state);
    final description = _EnrichmentHint._descriptionForState(loc, state);

    return Container(
      decoration: BoxDecoration(
        color: isCurrent ? color.withValues(alpha: 0.08) : null,
        border: Border(
          left: BorderSide(
            color: isCurrent ? color : OceanColors.transparent,
            width: 3,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: AppSpacing.s8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          loc.inatDeckStateExplainCurrent,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall,
                ),
              ],
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
