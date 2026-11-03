import 'package:discere/catalog/common/remove_swipe_background.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/common/species_selection.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The watchlist's swipe-to-remove species list. A long press starts selecting
/// several species; while selecting, a tap toggles a species and swiping is
/// off, so a slip of the finger cannot remove one.
class WatchlistSpeciesList extends StatelessWidget {
  static const SpeciesListItemPresenter _presenter = SpeciesListItemPresenter();

  final List<SpeciesWithLocalImages> items;
  final Language language;
  final SpeciesSelection selection;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onRemove;
  final ValueChanged<SpeciesSelection> onSelectionChanged;

  const WatchlistSpeciesList({
    super.key,
    required this.items,
    required this.language,
    required this.selection,
    required this.onOpen,
    required this.onRemove,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.elementSpacing),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final speciesId = item.species.id;
        void toggle() => onSelectionChanged(selection.toggled(speciesId));

        return Dismissible(
          key: Key(speciesId),
          direction: selection.isActive
              ? DismissDirection.none
              : DismissDirection.endToStart,
          background: const RemoveSwipeBackground(),
          onDismissed: (_) => onRemove(speciesId),
          child: SpeciesListItem(
            item: _presenter.presentSpeciesWithLocalImages(item, language),
            onTap: selection.isActive ? toggle : () => onOpen(speciesId),
            onLongPress: selection.isActive
                ? null
                : () => onSelectionChanged(
                    SpeciesSelection.startingWith(speciesId),
                  ),
            onDelete: () => onRemove(speciesId),
            trailing: selection.isActive
                ? Checkbox(
                    key: ValueKey('watchlist_selection_checkbox_$speciesId'),
                    value: selection.isSelected(speciesId),
                    onChanged: (_) => toggle(),
                  )
                : null,
          ),
        );
      },
    );
  }
}
