import 'package:discere/learning/decks/edit/species_selection.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// App bar of EditDeckPage while species are being selected: ends the
/// selection, says how many are selected, selects all or none, and offers what
/// can be done with them.
class SpeciesSelectionAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final SpeciesSelection selection;

  /// The species of the draft, for selecting all of them.
  final Set<String> speciesIds;
  final ValueChanged<SpeciesSelection> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onAssignSubdeck;

  const SpeciesSelectionAppBar({
    required this.selection,
    required this.speciesIds,
    required this.onChanged,
    required this.onDelete,
    required this.onAssignSubdeck,
    super.key,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final allSelected = selection.isAllSelected(speciesIds);
    return AppBar(
      leading: IconButton(
        key: const Key('edit_deck_selection_close_button'),
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        icon: const Icon(Icons.close),
        onPressed: () => onChanged(SpeciesSelection.none),
      ),
      title: Text(
        loc.editDeckSelectionCount(selection.selectedIds.length),
        key: const Key('edit_deck_selection_count'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          key: const Key('edit_deck_selection_all_button'),
          tooltip: allSelected
              ? loc.editDeckSelectionDeselectAll
              : loc.editDeckSelectionSelectAll,
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          onPressed: () => onChanged(selection.toggledAll(speciesIds)),
        ),
        IconButton(
          key: const Key('edit_deck_selection_delete_button'),
          tooltip: loc.editDeckSelectionDelete,
          icon: const Icon(Icons.delete_outline),
          onPressed: selection.hasSelection ? onDelete : null,
        ),
        IconButton(
          key: const Key('edit_deck_selection_assign_button'),
          tooltip: loc.editDeckSelectionAssign,
          icon: const Icon(Icons.drag_handle),
          onPressed: selection.hasSelection ? onAssignSubdeck : null,
        ),
      ],
    );
  }
}
