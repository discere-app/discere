import 'dart:io';

import 'package:discere/extensions/localization_extension.dart';
import 'package:discere/model/learning/deck_stat.dart';
import 'package:discere/theme/ocean_theme/ocean_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/ui/view_deck.dart';

import '../../service/learning/flashcard_service.dart';

class DeckCard extends StatelessWidget {
  final ViewDeck deck;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDismiss;

  const DeckCard({
    super.key,
    required this.deck,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onTap,
    required this.onEdit,
    required this.onShare,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
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
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDismiss(),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cover image
              AspectRatio(
                aspectRatio: 16 / 9,
                child: deck.coverImagePath != null
                    ? Image.file(
                        File(deck.coverImagePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: colorScheme.secondary.withValues(alpha: 0.5),
                          child: const Center(
                            child: Icon(Icons.image_not_supported,
                                size: 48, color: Colors.white54),
                          ),
                        ),
                      )
                    : Container(
                        color: colorScheme.secondary.withValues(alpha: 0.5),
                        child: const Center(
                          child: Icon(Icons.image_not_supported,
                              size: 48, color: Colors.white54),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
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
                              Text(deck.name,
                                  style: theme.textTheme.titleLarge),
                              const SizedBox(height: 4),
                              _StatSubtitle(deckId: deck.id!),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
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
                              icon: Icon(Icons.edit_square,
                                  color: colorScheme.onSurface),
                              onPressed: onEdit,
                            ),
                            IconButton(
                              icon: Icon(Icons.share,
                                  color: colorScheme.onSurface),
                              onPressed: onShare,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: deck.progress,
                        minHeight: 6,
                        backgroundColor:
                            colorScheme.onSurface.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          deck.progress >= 1.0
                              ? OceanColors.success
                              : colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Action button
                    _ActionButton(
                      deck: deck,
                      onTap: onTap,
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
}

/// Subtitle showing how many cards have been learned, loaded asynchronously.
class _StatSubtitle extends StatelessWidget {
  final String deckId;

  const _StatSubtitle({required this.deckId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<DeckStat>(
      future: Provider.of<FlashCardService>(context, listen: false)
          .getDeckStat(deckId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final stat = snapshot.data!;
        final learned = stat.totalCount - stat.uninitializedCount;
        return Text(
          context.loc.deckProgressSubtitle(learned, stat.totalCount),
          style: theme.textTheme.bodyMedium,
        );
      },
    );
  }
}

/// Start / Practice button shown at the bottom of the card.
class _ActionButton extends StatelessWidget {
  final ViewDeck deck;
  final VoidCallback onTap;

  const _ActionButton({required this.deck, required this.onTap});

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
        future: Provider.of<FlashCardService>(context, listen: false)
            .getDeckStat(deck.id!),
        builder: (context, snapshot) {
          final parts = <String>[];
          if (snapshot.hasData) {
            final stat = snapshot.data!;
            if (stat.dueCount > 0) {
              parts.add(context.loc.deckReviewButton(stat.dueCount));
            }
            if (stat.uninitializedCount > 0) {
              parts
                  .add(context.loc.deckNewCardsButton(stat.uninitializedCount));
            }
          }
          final label =
              parts.isNotEmpty ? parts.join('\n') : context.loc.commonPractice;
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
