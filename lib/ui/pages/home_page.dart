import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../service/learning/decks_service.dart';
import '../components/decks_view.dart';

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
