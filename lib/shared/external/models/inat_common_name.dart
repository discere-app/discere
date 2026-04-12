class INatCommonNamePlace {
  final int placeId;
  final int position;

  const INatCommonNamePlace({required this.placeId, required this.position});
}

class INatCommonName {
  final String languageCode;
  final String name;
  final int? position;
  final List<INatCommonNamePlace> places;

  const INatCommonName({
    required this.languageCode,
    required this.name,
    this.position,
    this.places = const [],
  });
}
