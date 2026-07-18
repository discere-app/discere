/// Shared SQL-building helpers for the locale-aware `common_names` lookups
/// used by species_repository.dart, search_repository.dart and
/// taxonomy_repository.dart. All three read the reference DB's
/// `common_names` table and want the same "user's country first, then
/// global" ordering; this used to be a hand-copied `.replaceAll()` trick in
/// each file.
library;

final _numericCountryCode = RegExp(r'^\d{1,4}$');

/// Returns [country] if it is a plain ISO-3166-1 numeric code (digits only),
/// else null.
///
/// All regional-preference clauses interpolate the country code into SQL
/// text rather than binding it as a parameter (the clauses are built by
/// string rewriting, so there is no argument list to extend). This guard is
/// the single choke point that makes that interpolation injection-safe:
/// interpolate only what passed through here.
String? sqlSafeCountryCode(String? country) {
  if (country == null || !_numericCountryCode.hasMatch(country)) return null;
  return country;
}

/// Injects a regional country preference into a `common_names` ORDER BY
/// clause. Replaces `(cn.country IS NULL) DESC` with a version that sorts
/// the given [country] first, then global names (`country IS NULL`), which
/// still rank above other countries.
///
/// No-op when [country] is null (unknown region) or not a valid numeric
/// code. [country] is an ISO-3166-1 numeric code, e.g. `'756'` for
/// Switzerland.
String withCountryPreference(String sql, String? country) {
  final safeCountry = sqlSafeCountryCode(country);
  if (safeCountry == null) return sql;
  return sql.replaceAll(
    '(cn.country IS NULL) DESC',
    "(cn.country = '$safeCountry') DESC, (cn.country IS NULL) DESC",
  );
}

/// Builds the correlated subquery that picks a single best `common_names`
/// row for `entityAlias.entityIdColumn` in [language]: the preferred
/// regional name if [withCountryPreference] has injected one, else the
/// global (country-less) preferred name, else the lowest-ranked name. The
/// result column is aliased to [outputAlias].
///
/// [entityAlias] and [entityIdColumn] are interpolated directly into the SQL
/// (they're always internal column/alias constants, never user input).
String commonNameSubquery({
  required String entityAlias,
  required String entityIdColumn,
  required String language,
  required String outputAlias,
}) {
  return '(SELECT cn.name FROM common_names cn '
      "WHERE cn.entity_id = $entityAlias.$entityIdColumn AND cn.language = '$language' "
      'ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) '
      'AS $outputAlias';
}
