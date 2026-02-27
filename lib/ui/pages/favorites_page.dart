import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../service/learning/decks_service.dart';
import '../../service/common/favorite_service.dart';
import '../components/decks_view.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<FavoriteService, DecksService>(
      builder: (context, favoriteService, decksService, child) {
        return DecksView(decksService.getDecks(favoriteService.getDecks()));
      },
    );
  }
}
