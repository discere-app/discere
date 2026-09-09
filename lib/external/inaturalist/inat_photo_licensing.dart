/// Which iNaturalist photos the app may show, and how one is read out of the
/// API's JSON.
///
/// The app redistributes these images inside a learning deck, so a photo is
/// only usable when its license permits that. Everything else is dropped
/// rather than shown with a caveat — a picture nobody may use is worse than
/// no picture.
///
/// Kept apart from the fetching so the rule can be stated and checked without
/// a network round trip.
library;

import 'package:discere/external/inaturalist/models/inat_photo.dart';

/// All CC license codes that are allowed for non-commercial use.
const _allowedLicenses = {
  'cc-by',
  'cc-by-sa',
  'cc-by-nc',
  'cc-by-nd',
  'cc-by-nc-sa',
  'cc-by-nc-nd',
  'cc0',
  'pd', // Public Domain (sometimes used instead of cc0)
};

/// Extracts curated photos from a taxon response.
List<INatPhoto> usablePhotosOf(Map<String, dynamic> taxon) {
  final photos = <INatPhoto>[];

  // Check taxon_photos array (expert-picked curated photos).
  final taxonPhotos = taxon['taxon_photos'] as List<dynamic>?;
  if (taxonPhotos != null) {
    for (final tp in taxonPhotos) {
      final photo = tp['photo'] as Map<String, dynamic>?;
      if (photo == null) continue;

      final inatPhoto = parsePhoto(photo);
      if (inatPhoto != null) photos.add(inatPhoto);
    }
  }

  // Secondary Fallback: use default_photo if no taxon_photos were found.
  if (photos.isEmpty) {
    final defaultPhoto = taxon['default_photo'] as Map<String, dynamic>?;
    if (defaultPhoto != null) {
      final inatPhoto = parsePhoto(defaultPhoto);
      if (inatPhoto != null) photos.add(inatPhoto);
    }
  }

  return photos;
}

/// Parses a single photo object from the API response.
/// Returns null if the photo has no usable CC license or URL.
INatPhoto? parsePhoto(Map<String, dynamic> photo) {
  final url = photo['url'] as String?;
  if (url == null || url.isEmpty) return null;

  final licenseCode = (photo['license_code'] as String?)?.toLowerCase();

  // Strict Filter: only allow CC-licensed photos for legal safety.
  if (licenseCode == null || !_allowedLicenses.contains(licenseCode)) {
    return null;
  }

  final attribution = photo['attribution'] as String?;

  return INatPhoto(
    url: url,
    attribution: attribution,
    licenseCode: licenseCode,
  );
}
