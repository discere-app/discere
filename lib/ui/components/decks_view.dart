import '../../theme/ocean_theme/ocean_colors.dart';
import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/learning/base_deck.dart';
import '../../model/learning/deck_stat.dart';
import '../../model/ui/view_deck.dart';
import '../../service/common/favorite_service.dart';
import '../../service/learning/decks_service.dart';
import '../../service/learning/flashcard_service.dart';
import '../pages/deck_page.dart';

class DecksView extends StatefulWidget {
  final Future<List<ViewDeck>> futureDecks;

  const DecksView(this.futureDecks, {super.key});

  @override
  DecksViewState createState() => DecksViewState();
}

class DecksViewState extends State<DecksView> {
  late DecksService _decksService;

  @override
  void initState() {
    super.initState();
    _decksService = Provider.of<DecksService>(context, listen: false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ViewDeck>>(
      future: widget.futureDecks,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(
              child: Text('${context.loc.error}:  ${snapshot.error}'));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text(context.loc.decksOverviewNoDeck));
        } else {
          return _buildDeckListView(snapshot.data!);
        }
      },
    );
  }


  Widget _buildDeckListView(List<ViewDeck> decks) {
    return Consumer<FavoriteService>(
      builder: (context, favoriteService, child) {
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: decks.length,
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final deck = decks[index];
            final isFavorite = favoriteService.isFavoriteDeck(deck.id!);
            return _buildDeckCard(context, deck, isFavorite, favoriteService);
          },
        );
      },
    );
  }

  Widget _buildDeckCard(BuildContext context, ViewDeck deck, bool isFavorite, FavoriteService favoriteService) {
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
      onDismissed: (direction) => _onDismissed(direction, deck.id!),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openDeck(context, deck),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Deck Cover Image (Gradient overlay omitted directly, or just placeholder fallback)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: deck.coverImagePath != null
                    ? Image.asset(deck.coverImagePath!, fit: BoxFit.cover)
                    : Container(
                        color: colorScheme.secondary.withOpacity(0.5),
                        child: const Center(
                          child: Icon(Icons.image_not_supported, size: 48, color: Colors.white54),
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
                              Text(deck.name, style: theme.textTheme.titleLarge),
                              const SizedBox(height: 4),
                              FutureBuilder<DeckStat>(
                                future: Provider.of<FlashCardService>(context, listen: false).getDeckStat(deck.id!),
                                builder: (context, statSnapshot) {
                                  if (statSnapshot.hasData) {
                                    final stat = statSnapshot.data!;
                                    return Text(
                                      '${stat.totalCount} Cards • ${stat.uninitializedCount} new cards',
                                      style: theme.textTheme.bodyMedium,
                                    );
                                  } else {
                                    return Text(
                                      '${context.loc.commonDescription}: ${deck.description}',
                                      style: theme.textTheme.bodyMedium,
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border,
                                  color: isFavorite ? colorScheme.primary : colorScheme.onSurface),
                              onPressed: () => favoriteService.toggleDeck(deck.id!),
                            ),
                            IconButton(
                              icon: Icon(Icons.edit_square, color: colorScheme.onSurface),
                              onPressed: () {
                                // TODO: Edit logic needs to be implemented.
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: deck.progress,
                        minHeight: 6,
                        backgroundColor: colorScheme.onSurface.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          deck.progress >= 1.0 ? OceanColors.success : colorScheme.primary, 
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Start Learning Button
                    SizedBox(
                      width: double.infinity,
                      child: deck.progress >= 1.0
                          ? ElevatedButton.icon(
                              onPressed: () => _openDeck(context, deck),
                              icon: const Icon(Icons.replay),
                              label: Text(context.loc.commonPractice), 
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary.withOpacity(0.2),
                                foregroundColor: colorScheme.primary,
                                elevation: 0,
                                side: BorderSide(color: colorScheme.primary.withOpacity(0.3)),
                              ),
                            )
                          : FutureBuilder<DeckStat>(
                              future: Provider.of<FlashCardService>(context, listen: false).getDeckStat(deck.id!),
                              builder: (context, statSnapshot) {
                                final label = statSnapshot.hasData && statSnapshot.data!.uninitializedCount > 0
                                    ? '${statSnapshot.data!.totalCount} Cards • ${statSnapshot.data!.uninitializedCount} new cards\n${context.loc.commonPractice}'
                                    : context.loc.commonPractice;
                                return ElevatedButton.icon(
                                  onPressed: () => _openDeck(context, deck),
                                  icon: const Icon(Icons.play_arrow),
                                  label: Text(label, textAlign: TextAlign.center), 
                                );
                              },
                            ),
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

  void _openDeck(BuildContext context, BaseDeck deck) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeckPage(deck: deck),
      ),
    );
  }

  void _onDismissed(DismissDirection direction, String deckId) {
    if (direction == DismissDirection.endToStart) {
      _decksService.deleteDeck(deckId);
    }
  }
}
