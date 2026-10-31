import 'package:discere/learning/model/subdeck.dart';
import 'package:discere/learning/model/subdeck_edit.dart';
import 'package:discere/learning/model/subdeck_structure.dart';
import 'package:flutter/foundation.dart';

/// The subdecks as the user is editing them on EditDeckPage: every operation
/// returns a new draft, and nothing is stored until the deck is saved.
class SubdeckDraft {
  /// In the order the user sees them.
  final List<SubdeckHeading> subdecks;

  /// The subdeck of each species that is in one, including species the page
  /// cannot show because the reference database does not resolve them.
  final Map<String, String> subdeckIdBySpeciesId;

  /// The subdecks switched on.
  final Set<String> activeSubdeckIds;

  const SubdeckDraft({
    required this.subdecks,
    required this.subdeckIdBySpeciesId,
    required this.activeSubdeckIds,
  });

  /// The draft of a deck as it is stored.
  factory SubdeckDraft.ofStored(
    List<Subdeck> subdecks,
    Map<String, String> subdeckIdBySpeciesId,
  ) => SubdeckDraft(
    subdecks: [for (final s in subdecks) (id: s.id, name: s.name)],
    subdeckIdBySpeciesId: subdeckIdBySpeciesId,
    activeSubdeckIds: {
      for (final s in subdecks)
        if (s.isActive) s.id,
    },
  );

  /// Whether another subdeck than [exceptSubdeckId] goes by [name], leading
  /// and trailing space and case aside.
  bool isNameTaken(String name, {String? exceptSubdeckId}) {
    final wanted = name.trim().toLowerCase();
    return subdecks.any(
      (subdeck) =>
          subdeck.id != exceptSubdeckId &&
          subdeck.name.trim().toLowerCase() == wanted,
    );
  }

  /// A new subdeck at the end, switched on and without species.
  SubdeckDraft add({required String id, required String name}) => SubdeckDraft(
    subdecks: [...subdecks, (id: id, name: name)],
    subdeckIdBySpeciesId: subdeckIdBySpeciesId,
    activeSubdeckIds: {...activeSubdeckIds, id},
  );

  SubdeckDraft rename(String subdeckId, String name) => SubdeckDraft(
    subdecks: [
      for (final subdeck in subdecks)
        subdeck.id == subdeckId ? (id: subdeckId, name: name) : subdeck,
    ],
    subdeckIdBySpeciesId: subdeckIdBySpeciesId,
    activeSubdeckIds: activeSubdeckIds,
  );

  /// Without [subdeckId]; its species stay in the deck, in no subdeck.
  SubdeckDraft remove(String subdeckId) => SubdeckDraft(
    subdecks: [
      for (final subdeck in subdecks)
        if (subdeck.id != subdeckId) subdeck,
    ],
    subdeckIdBySpeciesId: {
      for (final MapEntry(key: speciesId, value: id)
          in subdeckIdBySpeciesId.entries)
        if (id != subdeckId) speciesId: id,
    },
    activeSubdeckIds: activeSubdeckIds.difference({subdeckId}),
  );

  /// With the subdeck at [oldIndex] moved so that it ends up at [newIndex].
  SubdeckDraft reorder(int oldIndex, int newIndex) => SubdeckDraft(
    subdecks: List.of(subdecks)
      ..removeAt(oldIndex)
      ..insert(newIndex, subdecks[oldIndex]),
    subdeckIdBySpeciesId: subdeckIdBySpeciesId,
    activeSubdeckIds: activeSubdeckIds,
  );

  /// With the species of [among] divided by [selected]: a selected one moves
  /// to [subdeckId] from wherever it is, one not selected leaves it for no
  /// subdeck. Species outside [among] were not on offer and stay as they are.
  SubdeckDraft assign(
    String subdeckId, {
    required Set<String> selected,
    required Set<String> among,
  }) {
    final assignment = Map.of(subdeckIdBySpeciesId);
    for (final speciesId in among) {
      if (selected.contains(speciesId)) {
        assignment[speciesId] = subdeckId;
      } else if (assignment[speciesId] == subdeckId) {
        assignment.remove(speciesId);
      }
    }
    return SubdeckDraft(
      subdecks: subdecks,
      subdeckIdBySpeciesId: assignment,
      activeSubdeckIds: activeSubdeckIds,
    );
  }

  /// Without [speciesId]'s subdeck, for a species taken out of the deck: saved,
  /// that removal also clears what is stored, and one added again is in none.
  SubdeckDraft removeSpecies(String speciesId) => SubdeckDraft(
    subdecks: subdecks,
    subdeckIdBySpeciesId: Map.of(subdeckIdBySpeciesId)..remove(speciesId),
    activeSubdeckIds: activeSubdeckIds,
  );

  SubdeckDraft withActive(Set<String> activeSubdeckIds) => SubdeckDraft(
    subdecks: subdecks,
    subdeckIdBySpeciesId: subdeckIdBySpeciesId,
    activeSubdeckIds: activeSubdeckIds,
  );

  /// What saving this draft changes about the division [saved] describes, or
  /// null when it stays as it is. Which subdecks are on is not part of it:
  /// that is a setting, not a division of the deck.
  ///
  /// [removedSpeciesIds] leave the deck with this save, which takes them out
  /// of their subdecks by itself; that is no change to the division either.
  SubdeckEdit? editSince(
    SubdeckDraft saved, {
    required Set<String> removedSpeciesIds,
  }) {
    final speciesIds = {
      ...saved.subdeckIdBySpeciesId.keys,
      ...subdeckIdBySpeciesId.keys,
    }.difference(removedSpeciesIds);
    final moves = <String, String?>{
      for (final speciesId in speciesIds)
        if (subdeckIdBySpeciesId[speciesId] !=
            saved.subdeckIdBySpeciesId[speciesId])
          speciesId: subdeckIdBySpeciesId[speciesId],
    };
    if (moves.isEmpty && listEquals(subdecks, saved.subdecks)) return null;
    return SubdeckEdit(subdecks: subdecks, moves: moves);
  }

  /// Whether [other] holds the same subdecks in the same order, divides the
  /// species the same way and has the same ones on.
  bool hasSameContentAs(SubdeckDraft other) =>
      listEquals(subdecks, other.subdecks) &&
      mapEquals(subdeckIdBySpeciesId, other.subdeckIdBySpeciesId) &&
      setEquals(activeSubdeckIds, other.activeSubdeckIds);
}
