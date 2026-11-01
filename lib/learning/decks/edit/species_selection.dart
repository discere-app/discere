/// Which species of EditDeckPage's list are selected for an action on several
/// at once. While the selection [isActive], tapping a row toggles it instead
/// of opening the species.
class SpeciesSelection {
  final bool isActive;
  final Set<String> selectedIds;

  const SpeciesSelection._(this.isActive, this.selectedIds);

  /// Not selecting.
  static const none = SpeciesSelection._(false, {});

  /// Selecting, with nothing selected yet.
  static const empty = SpeciesSelection._(true, {});

  /// Selecting, with [speciesId] selected.
  factory SpeciesSelection.startingWith(String speciesId) =>
      SpeciesSelection._(true, {speciesId});

  bool isSelected(String speciesId) => selectedIds.contains(speciesId);

  bool get hasSelection => selectedIds.isNotEmpty;

  /// Deselecting the last species keeps the selection active.
  SpeciesSelection toggled(String speciesId) => SpeciesSelection._(
    true,
    isSelected(speciesId)
        ? selectedIds.difference({speciesId})
        : {...selectedIds, speciesId},
  );

  /// Whether every one of [speciesIds], at least one, is selected.
  bool isAllSelected(Set<String> speciesIds) =>
      speciesIds.isNotEmpty && selectedIds.containsAll(speciesIds);

  /// None of [speciesIds] when all of them are selected, otherwise all.
  SpeciesSelection toggledAll(Set<String> speciesIds) => SpeciesSelection._(
    true,
    isAllSelected(speciesIds) ? const {} : speciesIds,
  );
}
