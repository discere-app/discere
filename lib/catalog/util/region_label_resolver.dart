import 'package:discere/catalog/util/region_data/country_names.dart';
import 'package:discere/catalog/util/region_data/special_territory_names.dart';
import 'package:discere/catalog/util/region_data/subdivision_names.dart';
import 'package:discere/catalog/util/region_key.dart';
import 'package:discere/shared/model/language.dart';

/// Resolves a raw `taxonomy_distribution_regions.region_key`/`region_label`
/// value to a display name in [language].
///
/// Falls back to English per code rather than per language, so a language
/// with only some countries translated still names the rest. Subdivision
/// names are English in every language — see [subdivisionNames].
///
/// An unresolvable key is returned unchanged: it is a code the user might
/// still recognise, which beats an empty row. A subdivision that has no
/// curated name is dropped instead, leaving the country name — a
/// FishBase-internal code like `I557` names nothing a user could place.
String resolveCountryRegionLabel(
  String rawLabel, {
  Language language = Language.en,
}) {
  final key = RegionKey.parse(rawLabel);
  if (key == null) return rawLabel.trim();

  final countryName = _countryName(key, language);
  if (countryName == null) return key.raw;

  final subdivisionCode = key.subdivisionCode;
  if (subdivisionCode == null) return countryName;

  final subdivisionName = subdivisionNames[subdivisionCode];
  if (subdivisionName == null) return countryName;

  return '$countryName · $subdivisionName';
}

String? _countryName(RegionKey key, Language language) =>
    _localized(specialTerritoryNamesByLanguage, language, key.countryCode) ??
    _localized(countryNamesByLanguage, language, key.paddedCountryCode) ??
    _qualifiedMainlandName(key, language);

/// Best-effort, never-wrong name for a territory code that no table curates:
/// name the mainland country it hangs off, and keep the raw code visible so
/// it is clear this is a region *of* that country, not the country itself.
String? _qualifiedMainlandName(RegionKey key, Language language) {
  final mainland = key.mainlandCountryCode;
  if (mainland == null) return null;
  final countryName = _localized(countryNamesByLanguage, language, mainland);
  if (countryName == null) return null;
  return '$countryName (${key.countryCode})';
}

String? _localized(
  Map<Language, Map<String, String>> byLanguage,
  Language language,
  String? code,
) {
  if (code == null) return null;
  return byLanguage[language]?[code] ?? byLanguage[Language.en]?[code];
}
