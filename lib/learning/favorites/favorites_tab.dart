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

  @override
  Widget build(BuildContext context) {
    return Consumer2<FavoriteService, DecksService>(
      builder: (context, favoriteService, decksService, child) {
        return DecksContent(
          decksService
              .getDecks(favoriteService.getDecks())
              .warnOnFailure(_log, 'Favorite deck list load'),
          buildSpeciesDetailPage: widget.buildSpeciesDetailPage,
          onRefresh: () {
            if (!mounted) return;
            setState(() {});
          },
        );
      },
    );
  }
}
