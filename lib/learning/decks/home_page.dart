import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/decks/decks_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

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
          onRefresh: () {
            if (!mounted) return;
            setState(() {});
          },
        );
      },
    );
  }
}
