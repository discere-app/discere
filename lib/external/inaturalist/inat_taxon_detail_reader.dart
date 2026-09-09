/// Reads the fields the app needs out of an iNaturalist taxon detail
/// document.
///
/// One place, because the same document answers several questions: the photo
/// fetch takes its curated gallery from it and returns the Wikipedia link and
/// conservation status alongside, since they came for free in the same
/// response.
library;

/// The Wikipedia article iNaturalist links for this taxon, if any.
String? wikipediaUrlOf(Map<String, dynamic>? taxon) {
  final url = taxon?['wikipedia_url'] as String?;
  if (url == null || url.isEmpty) return null;
  return url;
}

/// Extracts the taxon's two-letter IUCN Red List status code (e.g. "vu"),
/// if iNaturalist has one on file under the IUCN authority specifically —
/// other authorities (state/regional/NGO listings) use non-standard codes
/// and would misrepresent an unrelated ranking as an IUCN category.
///
/// iNat's singular `conservation_status` is place-scoped: it's only
/// populated when iNat can resolve one "most relevant" status for the
/// (absent, in our case) request place, so it comes back null for any
/// species with several regional assessments on file even when a global
/// IUCN Red List entry exists — e.g. Esox lucius has 20+ national/regional
/// statuses and only shows up under `conservation_statuses`. Fall back to
/// scanning that full list for the first IUCN Red List entry.
/// The IUCN conservation status, taken from the taxon's conservation
/// record. Absent for most taxa.
String? iucnStatusOf(Map<String, dynamic>? taxon) {
  final direct = _iucnStatusFrom(
    taxon?['conservation_status'] as Map<String, dynamic>?,
  );
  if (direct != null) return direct;

  final statuses = taxon?['conservation_statuses'] as List<dynamic>?;
  if (statuses == null) return null;
  for (final entry in statuses) {
    final status = _iucnStatusFrom(entry as Map<String, dynamic>?);
    if (status != null) return status;
  }
  return null;
}

String? _iucnStatusFrom(Map<String, dynamic>? conservationStatus) {
  final authority = conservationStatus?['authority'] as String?;
  if (authority?.toLowerCase() != 'iucn red list') return null;

  final status = conservationStatus?['status'] as String?;
  if (status == null || status.isEmpty) return null;
  return status;
}
