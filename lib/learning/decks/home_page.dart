import 'package:discere/learning/decks/decks_view.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  final Widget Function(String speciesId, Language? language)
  buildSpeciesDetailPage;
  final GlobalKey? firstCardFavoriteKey;
  final GlobalKey? firstCardEditKey;
  final GlobalKey? firstCardShareKey;
  final VoidCallback? onDeckReviewReturned;

  const HomePage({
    required this.buildSpeciesDetailPage,
    super.key,
    this.firstCardFavoriteKey,
    this.firstCardEditKey,
    this.firstCardShareKey,
    this.onDeckReviewReturned,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return Consumer<DecksService>(
      builder: (context, decksService, child) {
        return DecksView(
          decksService.getAllDecks(),
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
