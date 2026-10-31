import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Heading of the edit page's species list: how many species the draft holds,
/// and the buttons that add one and start selecting several. Without
/// [showActions], as during a selection, the buttons are hidden and out of
/// reach but keep their space: a long press starts a selection, and the list
/// must not move the pressed row from under the finger.
class EditDeckSpeciesHeader extends StatelessWidget {
  final int speciesCount;
  final VoidCallback onAdd;
  final VoidCallback onSelect;
  final bool showActions;

  const EditDeckSpeciesHeader({
    required this.speciesCount,
    required this.onAdd,
    required this.onSelect,
    required this.showActions,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A Wrap, because count and both buttons do not fit one line on a phone.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          context.loc.editSpeciesInDeck(speciesCount),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Visibility(
          visible: showActions,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const Key('edit_deck_select_species_button'),
                onPressed: speciesCount == 0 ? null : onSelect,
                child: Text(context.loc.editDeckSelectSpeciesButton),
              ),
              FilledButton.tonalIcon(
                key: const Key('edit_deck_add_species_button'),
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.loc.editAddSpeciesButton),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
