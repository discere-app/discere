enum ClassificationRowType { species, genus, family, order, classType, superClass }

class ClassificationRowViewModel {
  final ClassificationRowType type;
  final String? id;
  final String scientificName;
  final String? commonName;

  const ClassificationRowViewModel({
    required this.type,
    this.id,
    required this.scientificName,
    this.commonName,
  });
}
