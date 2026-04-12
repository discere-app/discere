import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:discere/learning/decks/decks_view.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<FavoriteService, DecksService>(
      builder: (context, favoriteService, decksService, child) {
        return DecksView(
          decksService.getDecks(favoriteService.getDecks()),
          onRefresh: () {
            if (!mounted) return;
            setState(() {});
          },
        );
      },
    );
  }
}
