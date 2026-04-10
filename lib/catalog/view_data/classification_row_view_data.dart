enum ClassificationRowType { genus, family, order, classType, superClass }

class ClassificationRowViewData {
  final ClassificationRowType type;
  final String scientificName;
  final String? commonName;

  const ClassificationRowViewData({
    required this.type,
    required this.scientificName,
    this.commonName,
  });
}
