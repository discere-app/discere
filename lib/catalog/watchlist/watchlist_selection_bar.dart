import 'package:discere/catalog/common/species_selection.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Shown above the watchlist while species are being selected: ends the
/// selection, says how many are selected, and adds them to a comparison.
class WatchlistSelectionBar extends StatelessWidget {
  final SpeciesSelection selection;
  final VoidCallback onClose;
  final VoidCallback onAddToComparison;

  const WatchlistSelectionBar({
    required this.selection,
    required this.onClose,
    required this.onAddToComparison,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.elementSpacing,
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('watchlist_selection_close_button'),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
          Expanded(
            child: Text(
              loc.watchlistSelectionCount(selection.selectedIds.length),
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            key: const Key('watchlist_selection_compare_button'),
            tooltip: loc.comparisonAdd,
            icon: const Icon(Icons.compare),
            onPressed: selection.hasSelection ? onAddToComparison : null,
          ),
        ],
      ),
    );
  }
}
