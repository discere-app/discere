import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/decks/edit/subdeck_draft.dart';
import 'package:discere/learning/decks/edit/subdeck_name_dialog.dart';
import 'package:discere/learning/decks/edit/subdeck_species_page.dart';
import 'package:discere/learning/model/subdeck_membership.dart';
import 'package:discere/learning/model/subdeck_structure.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

enum _SubdeckAction { rename, assignSpecies, delete }

/// Edit-deck section for the deck's subdecks: a switch per subdeck, since only
/// species of the subdecks switched on are cards, plus what divides the deck
/// up — adding, renaming, deleting and sorting subdecks and assigning species
/// to them. Part of the draft like every other field: nothing takes effect
/// until the deck is saved, which is why deleting asks for no confirmation.
class SubdeckSection extends StatelessWidget {
  final SubdeckDraft draft;

  /// The species of the draft.
  final List<Species> species;
  final Language language;
  final ValueChanged<SubdeckDraft> onChanged;

  /// Coach-mark target for `EditDeckTutorial`, on the section title like
  /// the learning settings' one.
  final GlobalKey? titleKey;

  const SubdeckSection({
    required this.draft,
    required this.species,
    required this.language,
    required this.onChanged,
    this.titleKey,
    super.key,
  });

  Set<String> get _speciesIds => {for (final s in species) s.id};

  Future<void> _add(BuildContext context) async {
    final name = await showSubdeckNameDialog(
      context,
      title: context.loc.editDeckSubdeckAddTitle,
      isTaken: draft.isNameTaken,
    );
    if (name == null) return;
    onChanged(draft.add(id: const Uuid().v4(), name: name));
  }

  Future<void> _rename(BuildContext context, SubdeckHeading subdeck) async {
    final name = await showSubdeckNameDialog(
      context,
      title: context.loc.editDeckSubdeckRenameTitle,
      initialName: subdeck.name,
      isTaken: (name) => draft.isNameTaken(name, exceptSubdeckId: subdeck.id),
    );
    if (name == null) return;
    onChanged(draft.rename(subdeck.id, name));
  }

  Future<void> _assignSpecies(
    BuildContext context,
    SubdeckHeading subdeck,
  ) async {
    final selected = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => SubdeckSpeciesPage(
          subdeck: subdeck,
          draft: draft,
          species: species,
          language: language,
        ),
      ),
    );
    if (selected == null) return;
    onChanged(draft.assign(subdeck.id, selected: selected, among: _speciesIds));
  }

  void _setActive(String subdeckId, bool active) => onChanged(
    draft.withActive(
      active
          ? {...draft.activeSubdeckIds, subdeckId}
          : draft.activeSubdeckIds.difference({subdeckId}),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: titleKey,
          child: Text(
            context.loc.editDeckSubdecksTitle,
            style: theme.textTheme.titleSmall,
          ),
        ),
        AppSpacing.heightS8,
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16,
                  AppSpacing.s16,
                  AppSpacing.s16,
                  AppSpacing.s8,
                ),
                child: Text(
                  context.loc.editDeckSubdecksDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              _buildRows(context),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s8),
                child: TextButton.icon(
                  key: const Key('edit_deck_subdeck_add_button'),
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(context.loc.editDeckSubdeckAddButton),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRows(BuildContext context) {
    final membership = SubdeckMembership.of(
      _speciesIds,
      draft.subdeckIdBySpeciesId,
    );
    return ReorderableListView(
      shrinkWrap: true,
      // The page around it scrolls.
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) =>
          onChanged(draft.reorder(oldIndex, newIndex)),
      children: [
        for (final (index, subdeck) in draft.subdecks.indexed)
          _buildRow(context, index, subdeck, membership),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    int index,
    SubdeckHeading subdeck,
    SubdeckMembership membership,
  ) {
    final id = subdeck.id;
    final active = draft.activeSubdeckIds.contains(id);
    final enabled =
        !active || membership.canSwitchOff(id, draft.activeSubdeckIds);
    return Row(
      key: ValueKey(id),
      children: [
        ReorderableDragStartListener(
          key: Key('edit_deck_subdeck_drag_handle_$id'),
          index: index,
          child: const Padding(
            padding: EdgeInsets.all(AppSpacing.s8),
            child: Icon(Icons.drag_handle),
          ),
        ),
        Expanded(
          child: SwitchListTile(
            key: Key('edit_deck_subdeck_switch_$id'),
            contentPadding: EdgeInsets.zero,
            title: Text(subdeck.name),
            subtitle: Text(
              context.loc.subdeckSpeciesCount(
                membership.speciesCounts[id] ?? 0,
              ),
            ),
            value: active,
            onChanged: enabled ? (value) => _setActive(id, value) : null,
          ),
        ),
        _buildMenu(context, subdeck),
      ],
    );
  }

  Widget _buildMenu(BuildContext context, SubdeckHeading subdeck) {
    final loc = context.loc;
    return PopupMenuButton<_SubdeckAction>(
      key: Key('edit_deck_subdeck_menu_${subdeck.id}'),
      onSelected: (action) => switch (action) {
        _SubdeckAction.rename => _rename(context, subdeck),
        _SubdeckAction.assignSpecies => _assignSpecies(context, subdeck),
        _SubdeckAction.delete => onChanged(draft.remove(subdeck.id)),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          key: const Key('edit_deck_subdeck_menu_rename'),
          value: _SubdeckAction.rename,
          child: Text(loc.editDeckSubdeckRename),
        ),
        PopupMenuItem(
          key: const Key('edit_deck_subdeck_menu_assign_species'),
          value: _SubdeckAction.assignSpecies,
          enabled: species.isNotEmpty,
          child: Text(loc.editDeckSubdeckAssignSpecies),
        ),
        PopupMenuItem(
          key: const Key('edit_deck_subdeck_menu_delete'),
          value: _SubdeckAction.delete,
          child: Text(loc.editDeckSubdeckDelete),
        ),
      ],
    );
  }
}
