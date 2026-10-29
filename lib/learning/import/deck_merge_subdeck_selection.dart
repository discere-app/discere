import 'package:discere/learning/model/subdeck_membership.dart';
import 'package:discere/learning/model/subdeck_structure.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// The merge dialog's choice of the subdecks the merged deck has on: one
/// checkbox per subdeck, with its species count. A choice, not a setting
/// that applies at once — it takes effect only when the merge is confirmed.
class DeckMergeSubdeckSelection extends StatelessWidget {
  final List<SubdeckHeading> subdecks;
  final SubdeckMembership membership;
  final Set<String> activeSubdeckIds;
  final void Function(String subdeckId, bool active) onChanged;

  const DeckMergeSubdeckSelection({
    required this.subdecks,
    required this.membership,
    required this.activeSubdeckIds,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.deckMergeDialogSubdecks),
        for (final subdeck in subdecks) _checkboxFor(context, subdeck),
      ],
    );
  }

  Widget _checkboxFor(BuildContext context, SubdeckHeading subdeck) {
    final id = subdeck.id;
    final active = activeSubdeckIds.contains(id);
    final enabled = !active || membership.canSwitchOff(id, activeSubdeckIds);
    return CheckboxListTile(
      key: Key('deck_merge_subdeck_checkbox_$id'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(subdeck.name),
      subtitle: Text(
        context.loc.subdeckSpeciesCount(membership.speciesCounts[id] ?? 0),
      ),
      value: active,
      onChanged: enabled ? (value) => onChanged(id, value ?? false) : null,
    );
  }
}
