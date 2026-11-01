import 'package:discere/learning/decks/edit/subdeck_draft.dart';
import 'package:discere/learning/decks/edit/subdeck_name_dialog.dart';
import 'package:discere/learning/model/subdeck_structure.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Where the user wants the selected species to go. No choice at all is a null
/// from the sheet, which is why "no subdeck" needs a value of its own.
sealed class SubdeckTarget {
  const SubdeckTarget();
}

final class ExistingSubdeckTarget extends SubdeckTarget {
  final String subdeckId;

  const ExistingSubdeckTarget(this.subdeckId);
}

final class NoSubdeckTarget extends SubdeckTarget {
  const NoSubdeckTarget();
}

final class NewSubdeckTarget extends SubdeckTarget {
  const NewSubdeckTarget();
}

/// Asks where [speciesIds] should go and resolves to [draft] with them moved
/// there, through a new subdeck if the user wants one, or to null when the
/// user cancels at any point.
Future<SubdeckDraft?> chooseSubdeckFor(
  BuildContext context,
  SubdeckDraft draft,
  Set<String> speciesIds,
) async {
  final target = await showModalBottomSheet<SubdeckTarget>(
    context: context,
    builder: (_) => SubdeckTargetSheet(subdecks: draft.subdecks),
  );
  switch (target) {
    case null:
      return null;
    case ExistingSubdeckTarget(:final subdeckId):
      return draft.move(speciesIds, subdeckId);
    case NoSubdeckTarget():
      return draft.move(speciesIds, null);
    case NewSubdeckTarget():
      if (!context.mounted) return null;
      final subdeck = await askForNewSubdeck(context, draft);
      if (subdeck == null) return null;
      return draft
          .add(id: subdeck.id, name: subdeck.name)
          .move(speciesIds, subdeck.id);
  }
}

/// The subdecks to choose from. A deck without any has no use for "no subdeck":
/// its species are in none already.
class SubdeckTargetSheet extends StatelessWidget {
  final List<SubdeckHeading> subdecks;

  const SubdeckTargetSheet({required this.subdecks, super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    void choose(SubdeckTarget target) => Navigator.of(context).pop(target);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              loc.editDeckSelectionAssign,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final subdeck in subdecks)
            ListTile(
              key: Key('edit_deck_subdeck_target_${subdeck.id}'),
              leading: const Icon(Icons.folder_outlined),
              title: Text(subdeck.name),
              onTap: () => choose(ExistingSubdeckTarget(subdeck.id)),
            ),
          if (subdecks.isNotEmpty)
            ListTile(
              key: const Key('edit_deck_subdeck_target_none'),
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(loc.editDeckSubdeckTargetNone),
              onTap: () => choose(const NoSubdeckTarget()),
            ),
          ListTile(
            key: const Key('edit_deck_subdeck_target_new'),
            leading: const Icon(Icons.add),
            title: Text(loc.editDeckSubdeckAddTitle),
            onTap: () => choose(const NewSubdeckTarget()),
          ),
        ],
      ),
    );
  }
}
