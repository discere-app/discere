import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/decks/edit/subdeck_draft.dart';
import 'package:discere/learning/model/subdeck_structure.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/material.dart';

/// Which of the deck's [species] belong to [subdeck]: a checklist of all of
/// them, each showing the subdeck it is in now. Pops with the checked species
/// on confirming and with nothing on going back, which leaves the draft as it
/// was.
class SubdeckSpeciesPage extends StatefulWidget {
  final SubdeckHeading subdeck;
  final SubdeckDraft draft;
  final List<Species> species;
  final Language language;

  const SubdeckSpeciesPage({
    required this.subdeck,
    required this.draft,
    required this.species,
    required this.language,
    super.key,
  });

  @override
  State<SubdeckSpeciesPage> createState() => _SubdeckSpeciesPageState();
}

class _SubdeckSpeciesPageState extends State<SubdeckSpeciesPage> {
  static const _presenter = SpeciesListItemPresenter();

  late final Map<String, String> _subdeckNameById = {
    for (final subdeck in widget.draft.subdecks) subdeck.id: subdeck.name,
  };

  late final Set<String> _selected = {
    for (final species in widget.species)
      if (widget.draft.subdeckIdBySpeciesId[species.id] == widget.subdeck.id)
        species.id,
  };

  void _setSelected(String speciesId, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(speciesId);
      } else {
        _selected.remove(speciesId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.editDeckSubdeckSpeciesTitle(widget.subdeck.name)),
        actions: [
          TextButton(
            key: const Key('edit_deck_subdeck_species_confirm_button'),
            onPressed: () => Navigator.of(context).pop(_selected),
            child: Text(loc.commonOk),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView.builder(
          itemCount: widget.species.length,
          itemBuilder: (context, index) {
            final species = widget.species[index];
            final currentSubdeckId =
                widget.draft.subdeckIdBySpeciesId[species.id];
            return CheckboxListTile(
              key: Key('edit_deck_subdeck_species_tile_${species.id}'),
              title: Text(
                _presenter.presentSpecies(species, widget.language).primaryName,
              ),
              subtitle: Text(
                _subdeckNameById[currentSubdeckId] ??
                    loc.editDeckSubdeckSpeciesInNone,
              ),
              value: _selected.contains(species.id),
              onChanged: (value) => _setSelected(species.id, value ?? false),
            );
          },
        ),
      ),
    );
  }
}
