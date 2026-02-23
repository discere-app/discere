
import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/learning/base_deck.dart';
import '../../model/ui/view_deck.dart';
import '../../service/common/favorite_service.dart';
import '../../service/learning/decks_service.dart';
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
        return ListView.builder(
          itemCount: decks.length,
          itemBuilder: (context, index) {
            final isFavorite = favoriteService.isFavoriteDeck(decks[index].id!);
            return Dismissible(
              key: Key(decks[index].id!),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Theme.of(context).colorScheme.errorContainer,
                child: const Icon(
                  Icons.delete,
                  color: Colors.white,
                ),
              ),
              child: Card(
                child: ListTile(
                  title: Text(decks[index].name),
                  subtitle: Text(decks[index].description),
                  trailing: IconButton(
                    onPressed: () =>
                        favoriteService.toggleDeck(decks[index].id!),
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite
                          ? Theme.of(context).colorScheme.secondary
                          : null,
                    ),
                  ),
                  onLongPress: () {
                    // Hier können Edit/Delete Optionen hinzugefügt werden
                  },
                  onTap: () => _openDeck(context, decks[index]),
                ),
              ),
              onDismissed: (direction) =>
                  _onDismissed(direction, decks[index].id!),
            );
          },
        );
      },
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
