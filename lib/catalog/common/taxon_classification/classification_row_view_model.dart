enum ClassificationRowType {
  species,
  genus,
  family,
  order,
  classType,
  superClass,
}

class ClassificationRowViewModel {
  final ClassificationRowType type;
  final String? id;
  final String scientificName;
  final String? commonName;

  /// A source's rank placeholder ("Not assigned"): shown as unassigned rather
  /// than under [scientificName], still navigable by [id].
  final bool isPlaceholder;

  const ClassificationRowViewModel({
    required this.type,
    this.id,
    required this.scientificName,
    this.commonName,
    this.isPlaceholder = false,
  });
}
