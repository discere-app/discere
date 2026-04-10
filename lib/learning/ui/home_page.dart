import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/ui/decks_view.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DecksService>(
      builder: (context, decksService, child) {
        return DecksView(decksService.getAllDecks());
      },
    );
  }
}
