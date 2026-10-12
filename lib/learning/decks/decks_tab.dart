import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/learning/decks/decks_content.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/failure_logging.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DecksTab extends StatefulWidget {
  final Widget Function(String speciesId, Language? language)
  buildSpeciesDetailPage;
  final GlobalKey? firstCardFavoriteKey;
  final GlobalKey? firstCardEditKey;
  final GlobalKey? firstCardShareKey;
  final VoidCallback? onDeckReviewReturned;

  const DecksTab({
    required this.buildSpeciesDetailPage,
    super.key,
    this.firstCardFavoriteKey,
    this.firstCardEditKey,
    this.firstCardShareKey,
    this.onDeckReviewReturned,
  });

  @override
  State<DecksTab> createState() => _DecksTabState();
}

class _DecksTabState extends State<DecksTab> {
  static final _log = Logger.forType(DecksTab);

  late final DecksService _decksService;
  late Future<List<DeckViewModel>> _futureDecks;

  @override
  void initState() {
    super.initState();
    _decksService = context.read<DecksService>();
    _futureDecks = _loadDecks();
    _decksService.addListener(_reload);
  }

  @override
  void dispose() {
    _decksService.removeListener(_reload);
    super.dispose();
  }

  /// Fetches the list again. Runs when a deck changed (every write through
  /// [DecksService] notifies) and when the list asks for it after a review
  /// or an edit — not on a rebuild from above, such as a tab switch, which
  /// changes nothing this tab shows.
  void _reload() {
    if (!mounted) return;
    setState(() {
      _futureDecks = _loadDecks();
    });
  }

  Future<List<DeckViewModel>> _loadDecks() =>
      _decksService.getAllDecks().warnOnFailure(_log, 'Deck list load');

  @override
  Widget build(BuildContext context) {
    return DecksContent(
      _futureDecks,
      buildSpeciesDetailPage: widget.buildSpeciesDetailPage,
      onRefresh: _reload,
      firstCardFavoriteKey: widget.firstCardFavoriteKey,
      firstCardEditKey: widget.firstCardEditKey,
      firstCardShareKey: widget.firstCardShareKey,
      onDeckReviewReturned: widget.onDeckReviewReturned,
    );
  }
}
