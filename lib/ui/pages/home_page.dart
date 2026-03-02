import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/ui/view_deck.dart';
import '../../service/learning/decks_service.dart';
import '../components/decks_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  late Future<List<ViewDeck>> _futureDecks;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final decksService = Provider.of<DecksService>(context, listen: false);
    setState(() {
      _futureDecks = decksService.getAllDecks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DecksService>(
      builder: (context, decksService, child) {
        return DecksView(decksService.getAllDecks(), onRefresh: _refresh);
      },
    );
  }
}
