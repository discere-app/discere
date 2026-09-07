import 'package:discere/catalog/watchlist/watchlist_page.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/learning/decks/home_page.dart';
import 'package:discere/learning/favorites/favorites_page.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The three bottom-navigation tabs.
///
/// A tab is built on its first visit and then kept alive in an
/// [IndexedStack], so switching away and back preserves scroll position and
/// filters instead of tearing the previous tab's state down. Unvisited tabs
/// stay empty so first launch does not pay for screens the user may never
/// open.
class MainScreenTabs extends StatefulWidget {
  final int selectedIndex;
  final Widget Function(String speciesId, [Language? language])
  buildSpeciesDetailPage;
  final GlobalKey deckFavKey;
  final GlobalKey deckEditKey;
  final Future<void> Function() onDeckReviewReturned;

  const MainScreenTabs({
    required this.selectedIndex,
    required this.buildSpeciesDetailPage,
    required this.deckFavKey,
    required this.deckEditKey,
    required this.onDeckReviewReturned,
    super.key,
  });

  @override
  State<MainScreenTabs> createState() => _MainScreenTabsState();
}

class _MainScreenTabsState extends State<MainScreenTabs> {
  final Set<int> _visited = {};

  Widget _tab(int index) {
    switch (index) {
      case 0:
        return HomePage(
          buildSpeciesDetailPage: widget.buildSpeciesDetailPage,
          firstCardFavoriteKey: widget.deckFavKey,
          firstCardEditKey: widget.deckEditKey,
          onDeckReviewReturned: widget.onDeckReviewReturned,
        );
      case 1:
        return FavoritesPage(
          buildSpeciesDetailPage: widget.buildSpeciesDetailPage,
        );
      case 2:
        return WatchlistPage(
          resolveSpecies: Provider.of<SpeciesMediaService>(
            context,
            listen: false,
          ).resolveAllWithDownload,
          buildSpeciesDetailPage: widget.buildSpeciesDetailPage,
        );
      default:
        throw UnimplementedError('no widget for $index');
    }
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.selectedIndex);
    return IndexedStack(
      index: widget.selectedIndex,
      children: List.generate(
        3,
        (index) =>
            _visited.contains(index) ? _tab(index) : const SizedBox.shrink(),
      ),
    );
  }
}
