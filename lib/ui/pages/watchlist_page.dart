
import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/biology/species_with_local_images.dart';
import '../../service/common/watchlist_service.dart';
import '../../service/learning/flashcard_service.dart';
import '../components/image_carousel.dart';

class WatchListPage extends StatefulWidget {
  const WatchListPage({super.key});

  @override
  State<StatefulWidget> createState() => _WatchListState();
}

class _WatchListState extends State<WatchListPage> {
  late final WatchListService _watchlistService;
  late final FlashCardService _flashCardService;
  late Future<List<SpeciesWithLocalImages>> _futureFlashCards;

  @override
  void initState() {
    super.initState();
    _watchlistService = Provider.of<WatchListService>(context, listen: false);
    _flashCardService = Provider.of<FlashCardService>(context, listen: false);
    _futureFlashCards = _flashCardService
        .getFlashCardsForSpecies(_watchlistService.getSpecies());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WatchListService>(
        builder: (context, watchlistService, child) {
      return FutureBuilder<List<SpeciesWithLocalImages>>(
          future: _futureFlashCards,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(
                  child: Text('${context.loc.error}:  ${snapshot.error}'));
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(
                  child: Text('Keine Spezies in der Merkliste vorhanden'));
            } else {
              final flashcards = snapshot.data!;
              return LayoutBuilder(builder: (context, constraints) {
                return ListView.builder(
                    itemCount: flashcards.length,
                    itemBuilder: (context, index) {
                      return Dismissible(
                          key: Key(flashcards[index].species.id),
                          direction: DismissDirection.endToStart,
                          onDismissed: (direction) => _onDismissed(
                              direction, flashcards[index].species.id),
                          child: Card(
                              child: Column(children: [
                            SelectableText(
                              flashcards[index].species.getBinomialName(),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            flashcards[index].localImages.isEmpty
                                ? Center(
                                    child: Text(
                                        context.loc.commonNoPictureAvailable))
                                : ImageCarousel(
                                    images: flashcards[index].localImages,
                                    constraints: constraints)
                          ])));
                    });
              });
            }
          });
    });
  }

  void _onDismissed(DismissDirection direction, String speciesId) {
    _watchlistService.removeSpecies(speciesId);
  }
}
