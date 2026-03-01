import 'dart:io';

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
              return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: flashcards.length,
                  itemBuilder: (context, index) {
                    final theme = Theme.of(context);
                    return Dismissible(
                        key: Key(flashcards[index].species.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) => _onDismissed(
                            direction, flashcards[index].species.id),
                        child: Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: theme.colorScheme.outlineVariant ?? Colors.transparent),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // Leading Image
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: flashcards[index].localImages.isEmpty
                                      ? Container(
                                          width: 64,
                                          height: 64,
                                          color: theme.colorScheme.secondary.withOpacity(0.5),
                                          child: const Icon(Icons.image_not_supported, color: Colors.white54),
                                        )
                                      : Image.file(
                                          File(flashcards[index].localImages.first),
                                          width: 64,
                                          height: 64,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                                const SizedBox(width: 16),
                                // Middle Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        flashcards[index].species.getBinomialName(),
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        flashcards[index].species.getBinomialName(),
                                        style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                // Trailing Delete Button
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  color: theme.colorScheme.error,
                                  onPressed: () => _onDismissed(DismissDirection.endToStart, flashcards[index].species.id),
                                ),
                              ],
                            ),
                          ),
                        ));
                  });
            }
          });
    });
  }

  void _onDismissed(DismissDirection direction, String speciesId) {
    _watchlistService.removeSpecies(speciesId);
  }
}
