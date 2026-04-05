class INatCommonName {
  final String languageCode;
  final String name;
  final int? position;
  final int? placePosition;

  const INatCommonName({
    required this.languageCode,
    required this.name,
    this.position,
    this.placePosition,
  });
}
