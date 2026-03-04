import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/ui/view_deck.dart';
import '../../service/common/favorite_service.dart';
import '../../service/learning/decks_service.dart';
import '../pages/deck_page.dart';
import '../pages/edit_deck_page.dart';
import '../pages/share_deck_page.dart';
import 'deck_card.dart';

class DecksView extends StatefulWidget {
  final Future<List<ViewDeck>> futureDecks;
  final VoidCallback? onRefresh;

  const DecksView(this.futureDecks, {super.key, this.onRefresh});

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
            return DeckCard(
              deck: deck,
              isFavorite: isFavorite,
              onFavoriteToggle: () => favoriteService.toggleDeck(deck.id!),
              onTap: () => _openDeck(context, deck),
              onEdit: () => _editDeck(context, deck),
              onShare: () => _shareDeck(context, deck),
              onDismiss: () => _decksService.deleteDeck(deck.id!),
            );
          },
        );
      },
    );
  }

  void _openDeck(BuildContext context, ViewDeck deck) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeckPage(deck: deck),
      ),
    );
    widget.onRefresh?.call();
  }

  void _editDeck(BuildContext context, ViewDeck deck) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditDeckPage(deck: deck),
      ),
    );
    if (updated == true) widget.onRefresh?.call();
  }

  void _shareDeck(BuildContext context, ViewDeck deck) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShareDeckPage(deck: deck),
        fullscreenDialog: true,
      ),
    );
  }
}
