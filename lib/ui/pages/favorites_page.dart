import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../service/learning/decks_service.dart';
import '../../service/common/favorite_service.dart';
import '../components/decks_view.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FavoriteService>(
        builder: (context, favoriteService, child) {
      DecksService decksService =
          Provider.of<DecksService>(context, listen: false);
      FavoriteService favoriteService =
          Provider.of<FavoriteService>(context, listen: false);

      return DecksView(decksService.getDecks(favoriteService.getDecks()));
    });
  }
}
