/// Maps a source's raw licence key onto the handful of licence families the
/// credits page can actually explain.
///
/// The keys come from the ETL and are not a closed set, so the mapping is
/// deliberately forgiving: anything containing `NC` is treated as
/// non-commercial even when its exact spelling is new. Order matters — the
/// specific spellings are checked before that catch-all.
library;

enum SourceLicenseKind {
  /// Attribution only, commercial use allowed.
  ccBy,

  /// Attribution, non-commercial use only.
  ccByNonCommercial,

  /// All rights reserved.
  allRightsReserved,

  /// A key the page has no explanation for; shown without a description
  /// rather than guessed at.
  unknown,
}

SourceLicenseKind sourceLicenseKindFor(String licenseKey) {
  if (licenseKey == 'CC BY 4.0' || licenseKey == 'CC BY / CC0') {
    return SourceLicenseKind.ccBy;
  }
  if (licenseKey == 'CC BY-NC 4.0' || licenseKey.contains('NC')) {
    return SourceLicenseKind.ccByNonCommercial;
  }
  if (licenseKey == 'ARR') return SourceLicenseKind.allRightsReserved;
  return SourceLicenseKind.unknown;
}
