/// SQL for a species' full scientific name, shared by every query that shows,
/// searches or matches species by it, so that all of them name a species the
/// same way — and the same way as `Species.binomialName` does in Dart.
library;

/// The full scientific name of the species row aliased [species], joined to
/// its genus row as [genus]: genus and epithet; for a species without a genus
/// its [preferredScientificNameSql]; the epithet alone only when it has
/// neither.
String speciesScientificNameSql({
  required String species,
  required String genus,
}) =>
    "COALESCE($genus.name || ' ' || $species.name, "
    '${preferredScientificNameSql(species: species, genus: genus)}, '
    '$species.name)';

/// The preferred scientific name the source gives the species row aliased
/// [species] — only for a species without a genus (no row joined as
/// [genus]), whose epithet alone names nothing; `NULL` for a species with
/// one, whose full name is genus and epithet.
///
/// `species_scientific_names` holds at most one preferred name per source.
/// The one from the species' own source wins, then the first by source and
/// name, so every query picks the same one.
String preferredScientificNameSql({
  required String species,
  required String genus,
}) =>
    '''
CASE WHEN $genus.id IS NULL THEN (
  SELECT ssn.name
  FROM species_scientific_names ssn
  WHERE ssn.species_id = $species.id AND ssn.is_preferred = 1
  ORDER BY ssn.source = $species.external_source DESC, ssn.source, ssn.name
  LIMIT 1
) END''';
