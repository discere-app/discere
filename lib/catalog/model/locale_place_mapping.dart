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

  factory LocalePlaceMapping.fromMap(Map<String, dynamic> map) {
    return LocalePlaceMapping(
      locale: map['locale'] as String,
      languageCode: map['language_code'] as String,
      countryCodeAlpha2: map['country_code_alpha2'] as String,
      countryCodeNumeric: map['country_code_numeric'] as String,
      inatPlaceId: map['inat_place_id'] as int,
    );
  }
}
