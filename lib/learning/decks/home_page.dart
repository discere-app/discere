import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:discere/shared/model/language.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/decks/decks_view.dart';

class HomePage extends StatefulWidget {
  final Widget Function(String speciesId, Language? language)
  buildSpeciesDetailPage;

  const HomePage({required this.buildSpeciesDetailPage, super.key});

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
        );
      },
    );
  }
}
