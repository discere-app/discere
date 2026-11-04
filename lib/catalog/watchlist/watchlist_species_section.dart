import 'dart:async';

import 'package:discere/catalog/common/resolve_species_with_images.dart';
import 'package:discere/catalog/common/species_selection.dart';
import 'package:discere/catalog/common/species_with_images_loader.dart';
import 'package:discere/catalog/comparison/add_to_comparison_sheet.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/catalog/watchlist/watchlist_category_tabs.dart';
import 'package:discere/catalog/watchlist/watchlist_selection_bar.dart';
import 'package:discere/catalog/watchlist/watchlist_species_list.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The watchlist's species, filterable by class, from which several can be
/// selected and added to a comparison. Loaded through
/// [SpeciesWithImagesLoader].
class WatchlistSpeciesSection extends StatefulWidget {
  final ResolveSpeciesWithImages resolveFromCache;
  final ResolveSpeciesWithImages resolveWithDownload;
  final Widget Function(String speciesId) buildSpeciesDetailPage;

  const WatchlistSpeciesSection({
    super.key,
    required this.resolveFromCache,
    required this.resolveWithDownload,
    required this.buildSpeciesDetailPage,
  });

  @override
  State<StatefulWidget> createState() => _WatchlistSpeciesSectionState();
}

class _WatchlistSpeciesSectionState extends State<WatchlistSpeciesSection> {
  static final _log = Logger.forType(WatchlistSpeciesSection);

  late final WatchlistService _watchlistService;

  late final SpeciesWithImagesLoader _loader = SpeciesWithImagesLoader(
    resolveFromCache: widget.resolveFromCache,
    resolveWithDownload: widget.resolveWithDownload,
    onChanged: () => setState(() {}),
    log: _log,
  );

  /// null means "all species" — see [WatchlistCategoryTabs].
  String? _selectedClassName;

  SpeciesSelection _selection = SpeciesSelection.none;

  Set<String> _currentSpeciesIds = {};

  @override
  void initState() {
    super.initState();
    _watchlistService = Provider.of<WatchlistService>(context, listen: false);

    _currentSpeciesIds = _watchlistService.getSpecies().toSet();
    unawaited(_loader.load(_currentSpeciesIds));
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
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
          unawaited(_loader.load(_currentSpeciesIds));
        }

        return _body(context, language);
      },
    );
  }

  Widget _body(BuildContext context, Language language) {
    final species = _loader.species;

    if (species == null) {
      final loadError = _loader.loadError;
      return loadError != null
          ? _message(
              context.loc.errorWithDetail(context.loc.describeError(loadError)),
            )
          : const Center(child: CircularProgressIndicator());
    }
    if (species.isEmpty) {
      return _message(context.loc.watchlistEmpty);
    }

    final classNames = species.map(_classNameOf).toSet().toList()..sort();
    final filtered = _selectedClassName == null
        ? species
        : species
              .where((entry) => _classNameOf(entry) == _selectedClassName)
              .toList();

    return Column(
      children: [
        if (_selection.isActive)
          WatchlistSelectionBar(
            selection: _selection,
            onClose: () => _setSelection(SpeciesSelection.none),
            onAddToComparison: () => _addSelectionToComparison(species),
          ),
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
                  selection: _selection,
                  onOpen: _openSpeciesDetail,
                  onRemove: _onRemove,
                  onSelectionChanged: _setSelection,
                ),
        ),
      ],
    );
  }

  /// The class a watchlist entry is filed under; every class placeholder of
  /// the sources, and every chain that does not reach a class, shares one
  /// unassigned tab.
  String _classNameOf(SpeciesWithLocalImages entry) {
    final classification = entry.species.classification;
    final className = classification.classScientificName;
    return className == null ||
            classification.isPlaceholder(TaxonRank.classRank)
        ? context.loc.classificationUnassigned
        : className;
  }

  Widget _message(String text) {
    return Padding(
      padding: AppSpacing.emptyStatePaddingAll,
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }

  void _setSelection(SpeciesSelection selection) =>
      setState(() => _selection = selection);

  Future<void> _addSelectionToComparison(
    List<SpeciesWithLocalImages> species,
  ) async {
    final added = await showAddToComparisonSheet(
      context,
      speciesIds: _selection.selectedIds,
      speciesNames: {
        for (final entry in species)
          if (_selection.isSelected(entry.species.id))
            entry.species.getBinomialName(),
      },
    );
    if (added && mounted) _setSelection(SpeciesSelection.none);
  }

  void _onRemove(String speciesId) {
    _loader.removeOptimistically(speciesId);
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
