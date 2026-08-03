import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// A species with no findable photo, as shown in [showNoPhotoGapsDialog].
class NoPhotoGapSpecies {
  final String speciesId;
  final String displayName;

  const NoPhotoGapSpecies({required this.speciesId, required this.displayName});
}

/// Shown once a deck's image-enrichment stages complete and some species
/// still have no photo at all (neither a reference image nor an iNaturalist
/// match). Lets the user pick which of them to remove from the deck; species
/// left unchecked are acknowledged so this dialog doesn't ask about them
/// again.
///
/// Returns the set of species IDs the user checked for removal (possibly
/// empty, meaning "keep all").
Future<Set<String>> showNoPhotoGapsDialog(
  BuildContext context,
  List<NoPhotoGapSpecies> gapSpecies,
) async {
  final result = await showDialog<Set<String>>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _NoPhotoGapsDialog(gapSpecies: gapSpecies),
  );
  return result ?? const {};
}

class _NoPhotoGapsDialog extends StatefulWidget {
  final List<NoPhotoGapSpecies> gapSpecies;

  const _NoPhotoGapsDialog({required this.gapSpecies});

  @override
  State<_NoPhotoGapsDialog> createState() => _NoPhotoGapsDialogState();
}

class _NoPhotoGapsDialogState extends State<_NoPhotoGapsDialog> {
  final Set<String> _checkedForRemoval = <String>{};

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return AlertDialog(
      key: const Key('no_photo_gaps_dialog'),
      icon: const Icon(Icons.image_not_supported_outlined, size: 32),
      title: Text(loc.noPhotoGapsDialogTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.noPhotoGapsDialogMessage(widget.gapSpecies.length)),
              ...widget.gapSpecies.map(
                (species) => CheckboxListTile(
                  key: Key('no_photo_gap_checkbox_${species.speciesId}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(species.displayName),
                  subtitle: Text(loc.flashcardRemoveSpeciesButton),
                  value: _checkedForRemoval.contains(species.speciesId),
                  onChanged: (checked) {
                    setState(() {
                      if (checked ?? false) {
                        _checkedForRemoval.add(species.speciesId);
                      } else {
                        _checkedForRemoval.remove(species.speciesId);
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('no_photo_gaps_confirm_button'),
          onPressed: () => Navigator.of(context).pop(_checkedForRemoval),
          child: Text(loc.noPhotoGapsDialogConfirmButton),
        ),
      ],
    );
  }
}
