enum ClassificationRowType { genus, family, order, classType, superClass }

class ClassificationRowViewModel {
  final ClassificationRowType type;
  final String scientificName;
  final String? commonName;

  const ClassificationRowViewModel({
    required this.type,
    required this.scientificName,
    this.commonName,
  });
}
