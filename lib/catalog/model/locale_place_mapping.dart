class LocalePlaceMapping {
  final String locale;
  final String languageCode;
  final String countryCodeAlpha2;
  final String countryCodeNumeric;
  final int inatPlaceId;

  const LocalePlaceMapping({
    required this.locale,
    required this.languageCode,
    required this.countryCodeAlpha2,
    required this.countryCodeNumeric,
    required this.inatPlaceId,
  });
}
