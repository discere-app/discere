/// Decides, for a set of decks and the species they contain, which deck owns
/// each species and what enrichment it has consent for.
///
/// Two rules meet here, and both are easy to get subtly wrong:
///
/// **Dedup.** A species referenced by several decks is enriched once, by one
/// owner. An owner that is still valid is never taken away, so work already
/// in flight for it is not stranded; only a species whose owner has dropped
/// out is reassigned.
///
/// **Consent is additive.** `wants_inat_photos`/`wants_common_names` are OR'd
/// across every deck referencing the species and across what was already
/// stored — a species granted consent by one deck keeps it even if another
/// deck referencing it opts out, and a later call can only widen it. A deck
/// missing from a consent map counts as consenting, matching the defaults
/// callers that do not track per-deck consent rely on.
///
/// Kept apart from the writes so both rules can be stated against plain maps
/// instead of a seeded six-table database. The repository still applies the
/// whole plan in one transaction.
library;

/// What should be written for one species.
typedef SpeciesOwnershipAssignment = ({
  String speciesId,
  String ownerDeckId,
  List<String> deckIds,
  bool wantsInatPhotos,
  bool wantsCommonNames,
});

class SpeciesOwnershipPlan {
  /// Per species, the row to upsert — in the order they should be written.
  final List<SpeciesOwnershipAssignment> assignments;

  /// Species no longer part of any tracked deck's plan, whose rows go.
  final List<String> droppedSpeciesIds;

  const SpeciesOwnershipPlan({
    required this.assignments,
    required this.droppedSpeciesIds,
  });

  /// The owned species per deck, which is what the caller of
  /// `assignSpeciesOwners` gets back.
  Map<String, List<String>> ownedSpeciesByDeckId(List<String> allDeckIds) {
    final owned = <String, List<String>>{
      for (final deckId in allDeckIds) deckId: <String>[],
    };
    for (final assignment in assignments) {
      owned
          .putIfAbsent(assignment.ownerDeckId, () => <String>[])
          .add(assignment.speciesId);
    }
    return owned.map(
      (deckId, speciesIds) =>
          MapEntry(deckId, List<String>.unmodifiable(speciesIds)),
    );
  }
}

class SpeciesOwnershipPlanner {
  /// The species each deck wants tracked. Treated as authoritative: a species
  /// missing from every deck here is dropped.
  final Map<String, Set<String>> speciesIdsByDeckId;

  /// Decks in the order they should win an unclaimed species.
  final List<String> prioritizedDeckIds;

  final Map<String, bool> includeInatPhotosByDeckId;
  final Map<String, bool> includeCommonNamesByDeckId;

  /// Current `enrichment_species_work` rows: `species_id`, `owner_deck_id`,
  /// `wants_inat_photos`, `wants_common_names`.
  final List<Map<String, Object?>> existingSpeciesWorkRows;

  /// Current `enrichment_species_deck_membership` rows: `species_id`,
  /// `deck_id`.
  final List<Map<String, Object?>> existingMembershipRows;

  const SpeciesOwnershipPlanner({
    required this.speciesIdsByDeckId,
    required this.prioritizedDeckIds,
    required this.existingSpeciesWorkRows,
    required this.existingMembershipRows,
    this.includeInatPhotosByDeckId = const {},
    this.includeCommonNamesByDeckId = const {},
  });

  SpeciesOwnershipPlan plan() {
    final existingBySpeciesId = {
      for (final row in existingSpeciesWorkRows)
        row['species_id'] as String: row,
    };
    final existingDeckIdsBySpecies = <String, List<String>>{};
    for (final row in existingMembershipRows) {
      (existingDeckIdsBySpecies[row['species_id'] as String] ??= []).add(
        row['deck_id'] as String,
      );
    }

    final assignments = <SpeciesOwnershipAssignment>[];
    for (final speciesId in _speciesByDescendingDeckCount()) {
      final deckIds = prioritizedDeckIds
          .where(
            (deckId) => speciesIdsByDeckId[deckId]?.contains(speciesId) ?? false,
          )
          .toList(growable: false);
      if (deckIds.isEmpty) continue;

      final existing = existingBySpeciesId[speciesId];
      final existingOwner = existing?['owner_deck_id'] as String?;
      assignments.add((
        speciesId: speciesId,
        // Keep the current owner while it still references the species;
        // reassigning would strand whatever it already has in flight.
        ownerDeckId: deckIds.contains(existingOwner)
            ? existingOwner!
            : deckIds.first,
        deckIds: deckIds,
        wantsInatPhotos: _consent(
          stored: existing?['wants_inat_photos'],
          deckIds: deckIds,
          byDeckId: includeInatPhotosByDeckId,
        ),
        wantsCommonNames: _consent(
          stored: existing?['wants_common_names'],
          deckIds: deckIds,
          byDeckId: includeCommonNamesByDeckId,
        ),
      ));
    }

    return SpeciesOwnershipPlan(
      assignments: assignments,
      droppedSpeciesIds: _droppedSpeciesIds(
        stillPlanned: {for (final a in assignments) a.speciesId},
        existingDeckIdsBySpecies: existingDeckIdsBySpecies,
      ),
    );
  }

  /// Most widely shared species first, ties broken by id so the order is
  /// stable. Assigning those first is what makes the owner of a shared
  /// species the highest-priority deck that has it, rather than whichever
  /// deck happened to come first alphabetically.
  List<String> _speciesByDescendingDeckCount() {
    // Counted once up front: recomputing inside the comparator would rescan
    // every deck's species set on every comparison.
    final frequency = <String, int>{};
    for (final speciesIds in speciesIdsByDeckId.values) {
      for (final speciesId in speciesIds) {
        frequency[speciesId] = (frequency[speciesId] ?? 0) + 1;
      }
    }
    return frequency.keys.toList(growable: false)..sort((left, right) {
      final byFrequency = (frequency[right] ?? 0).compareTo(
        frequency[left] ?? 0,
      );
      return byFrequency != 0 ? byFrequency : left.compareTo(right);
    });
  }

  static bool _consent({
    required Object? stored,
    required List<String> deckIds,
    required Map<String, bool> byDeckId,
  }) =>
      (stored as int? ?? 0) == 1 ||
      deckIds.any((deckId) => byDeckId[deckId] ?? true);

  /// A species drops out only if one of the decks that referenced it is part
  /// of this plan. A species held solely by decks nobody asked about is left
  /// alone — this call knows nothing about them and must not speak for them.
  List<String> _droppedSpeciesIds({
    required Set<String> stillPlanned,
    required Map<String, List<String>> existingDeckIdsBySpecies,
  }) {
    final planned = prioritizedDeckIds.toSet();
    return [
      for (final row in existingSpeciesWorkRows)
        if (!stillPlanned.contains(row['species_id'] as String) &&
            (existingDeckIdsBySpecies[row['species_id'] as String] ?? const [])
                .any(planned.contains))
          row['species_id'] as String,
    ];
  }
}
