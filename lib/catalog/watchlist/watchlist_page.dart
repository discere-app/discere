import 'dart:async';

import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/catalog/watchlist/watchlist_category_tabs.dart';
import 'package:discere/catalog/watchlist/watchlist_species_list.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

typedef ResolveWatchlistSpecies =
    Future<List<SpeciesWithLocalImages>> Function(Set<String> speciesIds);

/// The watchlist tab.
///
/// Loads in two passes, because the two differ by orders of magnitude: what is
/// already on disk comes back in a few queries, while fetching the missing
/// images is bounded by the network and by iNaturalist's rate limit. The list
/// therefore renders from [resolveFromCache] and adopts [resolveWithDownload]'s
/// result whenever it arrives. Both passes return the same species in the same
/// order, so adopting the second one fills in images without resorting the list.
class WatchlistPage extends StatefulWidget {
  final ResolveWatchlistSpecies resolveFromCache;
  final ResolveWatchlistSpecies resolveWithDownload;
  final Widget Function(String speciesId) buildSpeciesDetailPage;

  const WatchlistPage({
    super.key,
    required this.resolveFromCache,
    required this.resolveWithDownload,
    required this.buildSpeciesDetailPage,
  });

  @override
  State<StatefulWidget> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  static final _log = Logger.forType(WatchlistPage);

  late final WatchlistService _watchlistService;

  /// Which load the page is showing. Bumped by every [_load], so a result that
  /// arrives after the watchlist has changed can be recognised as belonging to
  /// a list that is no longer on screen.
  int _loadGeneration = 0;

  /// The species on screen, or null while the first load is still running.
  /// A reload keeps the previous list visible instead of dropping back to a
  /// spinner and tearing the whole list down (which would also visually undo
  /// the Dismissible swipe animation that just ran).
  List<SpeciesWithLocalImages>? _species;
  Object? _loadError;

  /// null means "all species" — see [WatchlistCategoryTabs].
  String? _selectedClassName;

  Set<String> _currentSpeciesIds = {};

  @override
  void initState() {
    super.initState();
    _watchlistService = Provider.of<WatchlistService>(context, listen: false);

    _currentSpeciesIds = _watchlistService.getSpecies().toSet();
    unawaited(_load(_currentSpeciesIds));
  }

  Future<void> _load(Set<String> speciesIds) async {
    final generation = ++_loadGeneration;

    try {
      final cached = await widget.resolveFromCache(speciesIds);
      if (!_isCurrent(generation)) return;
      setState(() {
        _species = cached;
        _loadError = null;
      });
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() => _loadError = error);
      return;
    }

    try {
      final withImages = await widget.resolveWithDownload(speciesIds);
      if (!_isCurrent(generation)) return;
      setState(() => _species = withImages);
    } catch (error) {
      // The cached list is already on screen and is a usable watchlist. A
      // failed image fetch must not replace it with an error message.
      _log.warn('Watchlist image download failed: $error');
    }
  }

  /// Whether a result that just came back still belongs to what the page shows.
  ///
  /// Between starting a load and its answer the watchlist can have changed — a
  /// species swiped away or added — and the page has started a newer load for
  /// the new set. Applying the older set's result then would undo the
  /// optimistic removal in [_onRemove] and put the swiped entry back on screen,
  /// which also crashes the Dismissible that was already dismissed.
  bool _isCurrent(int generation) =>
      mounted && generation == _loadGeneration;

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
          unawaited(_load(_currentSpeciesIds));
        }

        return _body(context, language);
      },
    );
  }

  Widget _body(BuildContext context, Language language) {
    final species = _species;

    if (species == null) {
      return _loadError != null
          ? _message(
              context.loc.errorWithDetail(
                context.loc.describeError(_loadError),
              ),
            )
          : const Center(child: CircularProgressIndicator());
    }
    if (species.isEmpty) {
      return _message(context.loc.watchlistEmpty);
    }

    final classNames =
        species
            .map((entry) => entry.species.classification.classScientificName)
            .toSet()
            .toList()
          ..sort();
    final filtered = _selectedClassName == null
        ? species
        : species
              .where(
                (entry) =>
                    entry.species.classification.classScientificName ==
                    _selectedClassName,
              )
              .toList();

    return Column(
      children: [
        WatchlistCategoryTabs(
          classNames: classNames,
          selectedClassName: _selectedClassName,
          onSelected: (className) =>
              setState(() => _selectedClassName = className),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _message(context.loc.watchlistCategoryEmpty)
              : WatchlistSpeciesList(
                  items: filtered,
                  language: language,
                  onOpen: _openSpeciesDetail,
                  onRemove: _onRemove,
                ),
        ),
      ],
    );
  }

  Widget _message(String text) {
    return Padding(
      padding: AppSpacing.emptyStatePaddingAll,
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }

  void _onRemove(String speciesId) {
    // Invalidate whatever load is still in flight before removing: it was
    // started for a set that still contained this species, so its result would
    // put the dismissed entry back. Waiting for the reload below (via
    // WatchlistService.notifyListeners() -> hasChanged) to bump the generation
    // is too late — that happens a frame later, and a pending result can land
    // first.
    _loadGeneration++;
    // Remove optimistically from the shown list so the dismissed item doesn't
    // flicker back in while that reload is still resolving.
    setState(() {
      _species = _species
          ?.where((entry) => entry.species.id != speciesId)
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
