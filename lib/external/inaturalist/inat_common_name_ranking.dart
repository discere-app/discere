/// Reads iNaturalist's taxon-name rows and puts them in the order the app
/// should show them.
///
/// A taxon can carry dozens of names per language, of wildly differing
/// quality — regional variants, misspellings, trade names. The ranking is
/// what makes the first one usable as *the* common name.
///
/// Kept apart from the fetching because that ordering is a judgement about
/// data, not about HTTP, and is worth checking on its own.
library;

import 'package:discere/external/inaturalist/models/inat_common_name.dart';

const Map<String, String> supportedLexicons = {
  'english': 'en',
  'german': 'de',
  'french': 'fr',
  'spanish': 'es',
};

/// Normalizes the two response shapes used by iNaturalist for taxon names.
List<Map<String, dynamic>> taxonNameRowsOf(dynamic decoded) {
  if (decoded is List) {
    return decoded.whereType<Map<String, dynamic>>().toList();
  }
  if (decoded is Map<String, dynamic>) {
    final results = decoded['results'];
    if (results is List) {
      return results.whereType<Map<String, dynamic>>().toList();
    }
  }
  return const [];
}

/// Converts a raw taxon-name row into a supported localized common name.
INatCommonName? parseCommonName(Map<String, dynamic> row) {
  final name = (row['name'] as String?)?.trim();
  final lexicon = (row['lexicon'] as String?)?.trim().toLowerCase();
  if (name == null || name.isEmpty || lexicon == null || lexicon.isEmpty) {
    return null;
  }

  final languageCode = supportedLexicons[lexicon];
  if (languageCode == null) return null;

  return INatCommonName(
    languageCode: languageCode,
    name: name,
    position: row['position'] as int?,
    places: placesOf(row['place_taxon_names'] as List<dynamic>?),
  );
}

/// Extracts all place-specific rankings attached to a taxon name.
List<INatCommonNamePlace> placesOf(List<dynamic>? placeTaxonNames) {
  if (placeTaxonNames == null || placeTaxonNames.isEmpty) return const [];

  final places = <INatCommonNamePlace>[];
  for (final item in placeTaxonNames.whereType<Map<String, dynamic>>()) {
    final placeId = item['place_id'] as int?;
    final position = item['position'] as int?;
    if (placeId == null || position == null) continue;
    places.add(INatCommonNamePlace(placeId: placeId, position: position));
  }
  return places;
}

/// Orders and deduplicates common names using iNat ranking metadata.
List<INatCommonName> rankCommonNames(List<INatCommonName> commonNames) {
  int bestPlacePosition(INatCommonName cn) => cn.places.isEmpty
      ? 999999
      : cn.places.map((p) => p.position).reduce((a, b) => a < b ? a : b);

  final sorted = [...commonNames]
    ..sort((a, b) {
      final aPosition = a.position ?? 999999;
      final bPosition = b.position ?? 999999;
      if (aPosition != bPosition) return aPosition.compareTo(bPosition);

      final aPlacePosition = bestPlacePosition(a);
      final bPlacePosition = bestPlacePosition(b);
      if (aPlacePosition != bPlacePosition) {
        return aPlacePosition.compareTo(bPlacePosition);
      }

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  final result = <INatCommonName>[];
  final seen = <String>{};

  for (final cn in sorted) {
    final normalized = cn.name
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    if (normalized.isEmpty || seen.contains(normalized)) continue;
    seen.add(normalized);
    result.add(cn);
  }

  return result;
}
