import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../service/learning/decks_service.dart';
import '../components/decks_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {

  @override
  void initState() {
    super.initState();
  }

  void _refresh() {
    // This can still be used for pull-to-refresh to force a rebuild if desired
    setState(() {});
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
