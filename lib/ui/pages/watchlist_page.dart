import 'dart:io';

import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/biology/species_with_local_images.dart';
import '../../service/common/watchlist_service.dart';
import '../../service/learning/flashcard_service.dart';

class WatchListPage extends StatefulWidget {
  const WatchListPage({super.key});

  @override
  State<StatefulWidget> createState() => _WatchListState();
}

class _WatchListState extends State<WatchListPage> {
  late final WatchListService _watchlistService;
  late final FlashCardService _flashCardService;
  late Future<List<SpeciesWithLocalImages>> _futureFlashCards;
  String _selectedCategory = 'All Species';

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
              final Set<String> categoryClasses = flashcards.map((f) => f.species.classification.classScientificName).toSet();
              final List<String> categories = ['All Species', ...categoryClasses.toList()..sort()];
              
              final filteredCards = _selectedCategory == 'All Species'
                  ? flashcards
                  : flashcards.where((f) => f.species.classification.classScientificName == _selectedCategory).toList();

              final theme = Theme.of(context);
              return Column(
                children: [
                  // Category Tabs
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: categories.map((cat) {
                        final isSelected = cat == _selectedCategory;
                        return Padding(
                          padding: const EdgeInsets.only(right: 24),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedCategory = cat;
                              });
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  cat,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.6),
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 2,
                                  width: 24,
                                  decoration: BoxDecoration(
                                    color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  // Filtered List
                  Expanded(
                    child: filteredCards.isEmpty
                        ? const Center(child: Text('Keine Spezies in dieser Kategorie'))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: filteredCards.length,
                            itemBuilder: (context, index) {
                              final item = filteredCards[index];
                              
                              // Mock Status Logic
                              final statusHash = item.species.scientificName.length % 3;
                              final String statusLabel;
                              final Color statusColor;
                              final Color statusBgColor;
                              if (statusHash == 0) {
                                statusLabel = 'Endangered';
                                statusColor = Colors.orange.shade400;
                                statusBgColor = Colors.orange.shade900.withOpacity(0.3);
                              } else if (statusHash == 1) {
                                statusLabel = 'Vulnerable';
                                statusColor = Colors.yellow.shade400;
                                statusBgColor = Colors.yellow.shade900.withOpacity(0.3);
                              } else {
                                statusLabel = 'Least Concern';
                                statusColor = Colors.green.shade400;
                                statusBgColor = Colors.green.shade900.withOpacity(0.3);
                              }

                              return Dismissible(
                        key: Key(item.species.id),
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
                            direction, item.species.id),
                        child: Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // Leading Image
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: item.localImages.isEmpty
                                      ? Container(
                                          width: 64,
                                          height: 64,
                                          color: theme.colorScheme.secondary.withOpacity(0.5),
                                          child: const Icon(Icons.image_not_supported, color: Colors.white54),
                                        )
                                      : Image.file(
                                          File(item.localImages.first),
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
                                        item.species.getBinomialName(),
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.species.getBinomialName(),
                                        style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      // Status Badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusBgColor,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          statusLabel.toUpperCase(),
                                          style: TextStyle(
                                            color: statusColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Trailing Delete Button
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  color: theme.colorScheme.error,
                                  onPressed: () => _onDismissed(DismissDirection.endToStart, item.species.id),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          }
          });
    });
  }

  void _onDismissed(DismissDirection direction, String speciesId) {
    _watchlistService.removeSpecies(speciesId);
    setState(() {
      _futureFlashCards = _flashCardService
          .getFlashCardsForSpecies(_watchlistService.getSpecies());
    });
  }
}
