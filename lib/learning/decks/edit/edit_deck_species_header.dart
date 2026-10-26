import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Heading of the edit page's species list: how many species the draft
/// holds, and the button that adds one.
class EditDeckSpeciesHeader extends StatelessWidget {
  final int speciesCount;
  final VoidCallback onAdd;

  const EditDeckSpeciesHeader({
    required this.speciesCount,
    required this.onAdd,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            context.loc.editSpeciesInDeck(speciesCount),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        FilledButton.tonalIcon(
          key: const Key('edit_deck_add_species_button'),
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: Text(context.loc.editAddSpeciesButton),
        ),
      ],
    );
  }
}
