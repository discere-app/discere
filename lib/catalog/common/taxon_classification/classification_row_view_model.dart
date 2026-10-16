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

  /// `null` where the species' chain has no taxon at this rank.
  final String? scientificName;
  final String? commonName;

  /// A rank that assigns the species to no taxon, shown as unassigned rather
  /// than under [scientificName]: a source's rank placeholder ("Not
  /// assigned"), still navigable by [id], or a rank the chain does not reach,
  /// which has neither name nor id.
  final bool isUnassigned;

  const ClassificationRowViewModel({
    required this.type,
    this.id,
    required this.scientificName,
    this.commonName,
    this.isUnassigned = false,
  });
}
