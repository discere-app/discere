import 'package:discere/learning/decks/decks_content.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:discere/shared/model/language.dart';
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
  @override
  Widget build(BuildContext context) {
    return Consumer2<FavoriteService, DecksService>(
      builder: (context, favoriteService, decksService, child) {
        return DecksContent(
          decksService.getDecks(favoriteService.getDecks()),
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
