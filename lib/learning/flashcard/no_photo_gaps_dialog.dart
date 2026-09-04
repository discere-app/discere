import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// A species with no findable photo, as shown in [showNoPhotoGapsDialog].
class NoPhotoGapSpecies {
  final String speciesId;
  final String displayName;

  const NoPhotoGapSpecies({required this.speciesId, required this.displayName});
}

/// What the user chose in [showNoPhotoGapsDialog].
enum NoPhotoGapsAction {
  /// Only offered when [showNoPhotoGapsDialog]'s `offerEnrichment` is true —
  /// start a full (base + iNaturalist) enrichment pass for the whole deck.
  enrichDeck,

  /// Remove [NoPhotoGapsOutcome.speciesToRemove] from the deck.
  removeSelected,

  /// Only offered when `offerEnrichment` is true — do nothing, session-only
  /// (no species removed, none acknowledged, so the dialog asks again next
  /// time the deck is opened).
  skip,
}

/// Result of [showNoPhotoGapsDialog].
class NoPhotoGapsOutcome {
  final NoPhotoGapsAction action;

  /// Only meaningful when [action] is [NoPhotoGapsAction.removeSelected].
  final Set<String> speciesToRemove;

  const NoPhotoGapsOutcome(this.action, {this.speciesToRemove = const {}});
}

/// Shown once a deck's image-enrichment stages complete and some species
/// still have no photo at all (neither a reference image nor an iNaturalist
/// match).
///
/// When [offerEnrichment] is false (iNaturalist was already requested for
/// this deck, so a missing photo means it was genuinely never found), this
/// behaves as before: a single "Fertig" action removes the checked species;
/// anything left unchecked is expected to be acknowledged by the caller so
/// this dialog doesn't ask about it again.
///
/// When [offerEnrichment] is true (the deck only ever downloaded base data —
/// iNaturalist was never asked), the dialog additionally offers to start a
/// full enrichment pass instead, and an explicit "skip for now" action that
/// the caller must NOT persist (species should be asked about again next
/// time the deck is opened, since nothing was actually tried or decided).
Future<NoPhotoGapsOutcome> showNoPhotoGapsDialog(
  BuildContext context,
  List<NoPhotoGapSpecies> gapSpecies, {
  required bool offerEnrichment,
}) async {
  final result = await showDialog<NoPhotoGapsOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _NoPhotoGapsDialog(
      gapSpecies: gapSpecies,
      offerEnrichment: offerEnrichment,
    ),
  );
  return result ?? const NoPhotoGapsOutcome(NoPhotoGapsAction.skip);
}

class _NoPhotoGapsDialog extends StatefulWidget {
  final List<NoPhotoGapSpecies> gapSpecies;
  final bool offerEnrichment;

  const _NoPhotoGapsDialog({
    required this.gapSpecies,
    required this.offerEnrichment,
  });

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
              Text(
                widget.offerEnrichment
                    ? loc.noPhotoGapsDialogMessageBaseOnly(
                        widget.gapSpecies.length,
                      )
                    : loc.noPhotoGapsDialogMessage(widget.gapSpecies.length),
              ),
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
      actions: widget.offerEnrichment
          ? [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    key: const Key('no_photo_gaps_enrich_button'),
                    onPressed: () => Navigator.of(context).pop(
                      const NoPhotoGapsOutcome(NoPhotoGapsAction.enrichDeck),
                    ),
                    child: Text(loc.noPhotoGapsDialogEnrichButton),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('no_photo_gaps_remove_selected_button'),
                    onPressed: _checkedForRemoval.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(
                            NoPhotoGapsOutcome(
                              NoPhotoGapsAction.removeSelected,
                              speciesToRemove: _checkedForRemoval,
                            ),
                          ),
                    child: Text(loc.noPhotoGapsDialogRemoveSelectedButton),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('no_photo_gaps_skip_button'),
                    onPressed: () => Navigator.of(context).pop(
                      const NoPhotoGapsOutcome(NoPhotoGapsAction.skip),
                    ),
                    child: Text(loc.noPhotoGapsDialogSkipButton),
                  ),
                ],
              ),
            ]
          : [
              FilledButton(
                key: const Key('no_photo_gaps_confirm_button'),
                onPressed: () => Navigator.of(context).pop(
                  NoPhotoGapsOutcome(
                    NoPhotoGapsAction.removeSelected,
                    speciesToRemove: _checkedForRemoval,
                  ),
                ),
                child: Text(loc.noPhotoGapsDialogConfirmButton),
              ),
            ],
    );
  }
}
