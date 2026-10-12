import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/learning/decks/decks_content.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/failure_logging.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FavoritesTab extends StatefulWidget {
  final Widget Function(String speciesId, Language? language)
  buildSpeciesDetailPage;

  const FavoritesTab({required this.buildSpeciesDetailPage, super.key});

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
  static final _log = Logger.forType(FavoritesTab);

  late final FavoriteService _favoriteService;
  late final DecksService _decksService;
  late Future<List<DeckViewModel>> _futureDecks;

  @override
  void initState() {
    super.initState();
    _favoriteService = context.read<FavoriteService>();
    _decksService = context.read<DecksService>();
    _futureDecks = _loadDecks();
    _favoriteService.addListener(_reload);
    _decksService.addListener(_reload);
  }

  @override
  void dispose() {
    _favoriteService.removeListener(_reload);
    _decksService.removeListener(_reload);
    super.dispose();
  }

  /// Fetches the list again. Runs when a deck is favorited or unfavorited,
  /// when a deck changed (every write through [DecksService] notifies), and
  /// when the list asks for it after a review or an edit — not on a rebuild
  /// from above, such as a tab switch, which changes nothing this tab shows.
  void _reload() {
    if (!mounted) return;
    setState(() {
      _futureDecks = _loadDecks();
    });
  }

  Future<List<DeckViewModel>> _loadDecks() => _decksService
      .getDecks(_favoriteService.getDecks())
      .warnOnFailure(_log, 'Favorite deck list load');

  @override
  Widget build(BuildContext context) {
    return DecksContent(
      _futureDecks,
      buildSpeciesDetailPage: widget.buildSpeciesDetailPage,
      onRefresh: _reload,
    );
  }
}
