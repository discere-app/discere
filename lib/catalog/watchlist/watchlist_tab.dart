import 'package:discere/catalog/common/resolve_species_with_images.dart';
import 'package:discere/catalog/comparison/comparison_lists_section.dart';
import 'package:discere/catalog/watchlist/watchlist_species_section.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

enum _WatchlistView { species, comparisons }

/// The watchlist tab: the species on the watchlist, and the comparison lists,
/// one at a time.
///
/// Both stay mounted once shown, so switching between them keeps the
/// species' filter and selection. The comparisons are built on their first
/// visit only, so opening the watchlist does not pay for them.
class WatchlistTab extends StatefulWidget {
  final ResolveSpeciesWithImages resolveFromCache;
  final ResolveSpeciesWithImages resolveWithDownload;
  final Widget Function(String speciesId) buildSpeciesDetailPage;

  const WatchlistTab({
    super.key,
    required this.resolveFromCache,
    required this.resolveWithDownload,
    required this.buildSpeciesDetailPage,
  });

  @override
  State<WatchlistTab> createState() => _WatchlistTabState();
}

class _WatchlistTabState extends State<WatchlistTab> {
  _WatchlistView _view = _WatchlistView.species;
  bool _hasShownComparisons = false;

  void _show(_WatchlistView view) => setState(() {
    _view = view;
    if (view == _WatchlistView.comparisons) _hasShownComparisons = true;
  });

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.elementSpacing,
            AppSpacing.screenPadding,
            0,
          ),
          child: SegmentedButton<_WatchlistView>(
            segments: [
              ButtonSegment(
                value: _WatchlistView.species,
                icon: const Icon(Icons.bookmark_border),
                label: Text(
                  loc.watchlistViewSpecies,
                  key: const Key('watchlist_view_species'),
                ),
              ),
              ButtonSegment(
                value: _WatchlistView.comparisons,
                icon: const Icon(Icons.compare),
                label: Text(
                  loc.watchlistViewComparisons,
                  key: const Key('watchlist_view_comparisons'),
                ),
              ),
            ],
            selected: {_view},
            showSelectedIcon: false,
            onSelectionChanged: (selected) => _show(selected.single),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _view.index,
            children: [
              WatchlistSpeciesSection(
                resolveFromCache: widget.resolveFromCache,
                resolveWithDownload: widget.resolveWithDownload,
                buildSpeciesDetailPage: widget.buildSpeciesDetailPage,
              ),
              if (_hasShownComparisons)
                const ComparisonListsSection()
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}
