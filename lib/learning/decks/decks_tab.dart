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

  @override
  Widget build(BuildContext context) {
    return Consumer<DecksService>(
      builder: (context, decksService, child) {
        return DecksContent(
          // Fetched on every rebuild on purpose: a tab switch or the return
          // from another page rebuilds this tab, and that is what brings the
          // deck cards' due counts up to date — nothing else does. Each
          // failure logged is therefore a fetch that actually failed.
          decksService.getAllDecks().warnOnFailure(_log, 'Deck list load'),
          buildSpeciesDetailPage: widget.buildSpeciesDetailPage,
          onRefresh: () {
            if (!mounted) return;
            setState(() {});
          },
          firstCardFavoriteKey: widget.firstCardFavoriteKey,
          firstCardEditKey: widget.firstCardEditKey,
          firstCardShareKey: widget.firstCardShareKey,
          onDeckReviewReturned: widget.onDeckReviewReturned,
        );
      },
    );
  }
}
