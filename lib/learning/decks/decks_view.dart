import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_spacing.dart';
import 'package:discere/learning/model/view_deck.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/flashcard/deck_page.dart';
import 'package:discere/learning/decks/edit_deck_page.dart';
import 'package:discere/learning/share/share_deck_page.dart';
import 'deck_card.dart';

class DecksView extends StatefulWidget {
  final Future<List<ViewDeck>> futureDecks;
  final VoidCallback? onRefresh;
  final Widget Function(String speciesId, Language? language)
  buildSpeciesDetailPage;
  final GlobalKey? firstCardFavoriteKey;
  final GlobalKey? firstCardEditKey;
  final GlobalKey? firstCardShareKey;

  const DecksView(
    this.futureDecks, {
    required this.buildSpeciesDetailPage,
    super.key,
    this.onRefresh,
    this.firstCardFavoriteKey,
    this.firstCardEditKey,
    this.firstCardShareKey,
  });

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
          return Padding(
            padding: AppSpacing.emptyStatePaddingAll,
            child: Center(
              child: Text(
                '${context.loc.error}:  ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Padding(
            padding: AppSpacing.emptyStatePaddingAll,
            child: Center(
              child: Text(
                context.loc.decksOverviewNoDeck,
                textAlign: TextAlign.center,
              ),
            ),
          );
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
          key: const Key('home_deck_list'),
          padding: AppSpacing.screenPaddingAll,
          itemCount: decks.length,
          separatorBuilder: (context, index) => AppSpacing.heightS16,
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
              favoriteKey: index == 0 ? widget.firstCardFavoriteKey : null,
              editKey: index == 0 ? widget.firstCardEditKey : null,
              shareKey: index == 0 ? widget.firstCardShareKey : null,
            );
          },
        );
      },
    );
  }

  void _openDeck(BuildContext context, ViewDeck deck) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DeckPage(deck: deck)),
    );
    widget.onRefresh?.call();
  }

  void _editDeck(BuildContext context, ViewDeck deck) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditDeckPage(
          deck: deck,
          buildSpeciesDetailPage: widget.buildSpeciesDetailPage,
        ),
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
