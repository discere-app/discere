import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class WatchlistPage extends StatefulWidget {
  final Future<List<SpeciesWithLocalImages>> Function(Set<String> speciesIds)
  resolveSpecies;
  final Widget Function(String speciesId) buildSpeciesDetailPage;

  const WatchlistPage({
    super.key,
    required this.resolveSpecies,
    required this.buildSpeciesDetailPage,
  });

  @override
  State<StatefulWidget> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  static const SpeciesListItemPresenter _speciesListItemPresenter =
      SpeciesListItemPresenter();
  late final WatchlistService _watchlistService;
  late Future<List<SpeciesWithLocalImages>> _futureFlashCards;
  String _selectedCategory = 'ALL_SPECIES';
  Set<String> _currentSpeciesIds = {};

  // Keeps the previously loaded list on screen while a refreshed
  // [_futureFlashCards] is still resolving, instead of dropping back to a
  // spinner and tearing down the whole list (which would also visually
  // undo the Dismissible swipe animation that just ran).
  List<SpeciesWithLocalImages>? _lastFlashcards;

  @override
  void initState() {
    super.initState();
    _watchlistService = Provider.of<WatchlistService>(context, listen: false);

    _currentSpeciesIds = _watchlistService.getSpecies().toSet();
    _futureFlashCards = widget.resolveSpecies(_currentSpeciesIds);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WatchlistService>(
      builder: (context, watchlistService, child) {
        final language = context.watch<LanguageService>().getLanguage();
        final newSpeciesIds = watchlistService.getSpecies();
        final hasChanged =
            _currentSpeciesIds.length != newSpeciesIds.length ||
            !_currentSpeciesIds.containsAll(newSpeciesIds);

        if (hasChanged) {
          _currentSpeciesIds = newSpeciesIds.toSet();
          _futureFlashCards = widget.resolveSpecies(_currentSpeciesIds);
        }

        return FutureBuilder<List<SpeciesWithLocalImages>>(
          future: _futureFlashCards,
          builder: (context, snapshot) {
            // FutureBuilder retains the *previous* future's snapshot data
            // while transitioning to `waiting` after a future-identity
            // change (AsyncSnapshot.inState() carries `data` over). So
            // `snapshot.hasData` alone can't distinguish "fresh result" from
            // "stale data from the future we just replaced" — only trust it
            // once this snapshot's own future has actually completed.
            if (snapshot.connectionState == ConnectionState.done &&
                snapshot.hasData) {
              _lastFlashcards = snapshot.data;
            }
            final flashcards = _lastFlashcards;
            final isFirstLoad = flashcards == null;

            if (snapshot.connectionState == ConnectionState.waiting &&
                isFirstLoad) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError && isFirstLoad) {
              return Padding(
                padding: AppSpacing.emptyStatePaddingAll,
                child: Center(
                  child: Text(
                    '${context.loc.error}:  ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            } else if (flashcards == null || flashcards.isEmpty) {
              return Padding(
                padding: AppSpacing.emptyStatePaddingAll,
                child: Center(
                  child: Text(
                    context.loc.watchlistEmpty,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            } else {
              final Set<String> categoryClasses = flashcards
                  .map((f) => f.species.classification.classScientificName)
                  .toSet();
              final List<String> categories = [
                'ALL_SPECIES',
                ...categoryClasses.toList()..sort(),
              ];

              final filteredCards = _selectedCategory == 'ALL_SPECIES'
                  ? flashcards
                  : flashcards
                        .where(
                          (f) =>
                              f.species.classification.classScientificName ==
                              _selectedCategory,
                        )
                        .toList();

              final theme = Theme.of(context);
              return Column(
                children: [
                  // Category Tabs
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenPadding,
                      vertical: AppSpacing.elementSpacing,
                    ),
                    child: Row(
                      children: categories.map((cat) {
                        final isSelected = cat == _selectedCategory;
                        return Padding(
                          padding: const EdgeInsets.only(
                            right: AppSpacing.groupSpacing,
                          ),
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
                                  cat == 'ALL_SPECIES'
                                      ? context.loc.watchlistAllSpecies
                                      : cat,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface
                                              .withValues(alpha: 0.6),
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                  ),
                                ),
                                AppSpacing.heightS8,
                                Container(
                                  height: 2,
                                  width: 24,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : Colors.transparent,
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
                        ? Padding(
                            padding: AppSpacing.emptyStatePaddingAll,
                            child: Center(
                              child: Text(
                                context.loc.watchlistCategoryEmpty,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.elementSpacing,
                            ),
                            itemCount: filteredCards.length,
                            itemBuilder: (context, index) {
                              final item = filteredCards[index];

                              return Dismissible(
                                key: Key(item.species.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(
                                    right: AppSpacing.s20,
                                  ),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.screenPadding,
                                    vertical: AppSpacing.elementSpacing,
                                  ),
                                  child: const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                  ),
                                ),
                                onDismissed: (direction) =>
                                    _onDismissed(direction, item.species.id),
                                child: SpeciesListItem(
                                  item: _speciesListItemPresenter
                                      .presentSpeciesWithLocalImages(
                                        item,
                                        language,
                                      ),
                                  onTap: () =>
                                      _openSpeciesDetail(item.species.id),
                                  onDelete: () => _onDismissed(
                                    DismissDirection.endToStart,
                                    item.species.id,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            }
          },
        );
      },
    );
  }

  void _onDismissed(DismissDirection direction, String speciesId) {
    // Remove optimistically from the cached list so the dismissed item
    // doesn't flicker back in while the reload triggered below (via
    // WatchlistService.notifyListeners() -> hasChanged) is still resolving.
    setState(() {
      _lastFlashcards = _lastFlashcards
          ?.where((f) => f.species.id != speciesId)
          .toList();
    });
    _watchlistService.removeSpecies(speciesId);
  }

  void _openSpeciesDetail(String speciesId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => widget.buildSpeciesDetailPage(speciesId),
      ),
    );
  }
}
