/// Raw SQL text for [SearchRepository]'s reference/runtime-common-name
/// queries. Kept as plain string-building functions (not query execution) so
/// the repository stays focused on orchestration — which queries to run, in
/// what order, against which database — while the query text itself lives in
/// one place.
library;

/// Species-only FTS lookup used by the "quick search while typing" path.
/// Faster than [referenceFtsUnionAllSql] because it skips genus/family/
/// order/class matches and the common-name FTS branches.
String referenceSpeciesFtsSql(int resultLimit) => '''
  SELECT s.id,
         g.name || ' ' || s.name AS scientific_name,
         'species' AS entity_type
  FROM species s
  JOIN genera g ON g.id = s.genus
  WHERE s.status = 'active'
    AND s.id IN (SELECT id FROM species_fts WHERE species_fts MATCH ?)
  LIMIT $resultLimit
''';

/// Full reference-DB FTS lookup: a single `UNION ALL` across 9 FTS
/// sub-queries (5 scientific-name tables + 4 common-name lookups), so
/// sqflite performs one DB round-trip instead of 9. Expects the same
/// wildcard term bound 9 times, in the order the sub-queries appear below.
///
/// IMPORTANT — query planner workaround:
/// Every FTS lookup uses `WHERE id IN (SELECT id FROM *_fts WHERE MATCH ?)`
/// instead of `FROM *_fts JOIN entity ON ...`. With a direct JOIN, SQLite's
/// planner starts from the entity table (scanning 138K+ species via
/// idx_species_status) and checks each row against the FTS virtual table,
/// resulting in 20–100+ second queries. The IN-subquery form forces it to
/// evaluate FTS first (typically returning a handful of rowids), then look
/// up only those specific entities — bringing query time to < 300 ms even
/// on low-end Android devices.
String referenceFtsUnionAllSql(int resultLimit) => '''
  SELECT id, scientific_name, entity_type FROM (
    SELECT s.id AS id, g.name || ' ' || s.name AS scientific_name, 'species' AS entity_type
    FROM species s
    JOIN genera g ON g.id = s.genus
    WHERE s.status = 'active'
      AND s.id IN (SELECT id FROM species_fts WHERE species_fts MATCH ?)
    LIMIT $resultLimit
  )
  UNION ALL
  SELECT id, scientific_name, entity_type FROM (
    SELECT s.id AS id, g.name || ' ' || s.name AS scientific_name, 'species' AS entity_type
    FROM species s
    JOIN genera g ON g.id = s.genus
    WHERE s.status = 'active'
      AND s.id IN (
        SELECT cn.entity_id FROM common_names cn
        WHERE cn.rowid IN (SELECT rowid FROM common_names_fts WHERE common_names_fts MATCH ?)
          AND cn.entity_type = 'species'
      )
    LIMIT $resultLimit
  )
  UNION ALL
  SELECT id, scientific_name, entity_type FROM (
    SELECT id AS id, name AS scientific_name, 'genera' AS entity_type
    FROM genera
    WHERE id IN (SELECT id FROM genera_fts WHERE genera_fts MATCH ?)
    LIMIT $resultLimit
  )
  UNION ALL
  SELECT id, scientific_name, entity_type FROM (
    SELECT g.id AS id, g.name AS scientific_name, 'genera' AS entity_type
    FROM genera g
    WHERE g.id IN (
      SELECT cn.entity_id FROM common_names cn
      WHERE cn.rowid IN (SELECT rowid FROM common_names_fts WHERE common_names_fts MATCH ?)
        AND cn.entity_type = 'genus'
    )
    LIMIT $resultLimit
  )
  UNION ALL
  SELECT id, scientific_name, entity_type FROM (
    SELECT id AS id, name AS scientific_name, 'families' AS entity_type
    FROM families
    WHERE id IN (SELECT id FROM families_fts WHERE families_fts MATCH ?)
    LIMIT $resultLimit
  )
  UNION ALL
  SELECT id, scientific_name, entity_type FROM (
    SELECT f.id AS id, f.name AS scientific_name, 'families' AS entity_type
    FROM families f
    WHERE f.id IN (
      SELECT cn.entity_id FROM common_names cn
      WHERE cn.rowid IN (SELECT rowid FROM common_names_fts WHERE common_names_fts MATCH ?)
        AND cn.entity_type = 'family'
    )
    LIMIT $resultLimit
  )
  UNION ALL
  SELECT id, scientific_name, entity_type FROM (
    SELECT id AS id, name AS scientific_name, 'orders' AS entity_type
    FROM orders
    WHERE id IN (SELECT id FROM orders_fts WHERE orders_fts MATCH ?)
    LIMIT $resultLimit
  )
  UNION ALL
  SELECT id, scientific_name, entity_type FROM (
    SELECT o.id AS id, o.name AS scientific_name, 'orders' AS entity_type
    FROM orders o
    WHERE o.id IN (
      SELECT cn.entity_id FROM common_names cn
      WHERE cn.rowid IN (SELECT rowid FROM common_names_fts WHERE common_names_fts MATCH ?)
        AND cn.entity_type = 'order'
    )
    LIMIT $resultLimit
  )
  UNION ALL
  SELECT id, scientific_name, entity_type FROM (
    SELECT id AS id, name AS scientific_name, 'classes' AS entity_type
    FROM classes
    WHERE id IN (SELECT id FROM classes_fts WHERE classes_fts MATCH ?)
    LIMIT $resultLimit
  )
''';

/// `LIKE`-based fallback statements, one per reference table, used only when
/// the FTS path above returned nothing (e.g. the term is too short for FTS
/// tokenization). Each expects two bound `%term%` arguments: one for the
/// scientific-name match, one for the common-name `EXISTS` subquery.
List<String> referenceLikeFallbackSqlStatements(int resultLimit) => [
  '''
    SELECT s.id, g.name || ' ' || s.name AS scientific_name, 'species' AS entity_type
    FROM species s
    JOIN genera g ON g.id = s.genus
    WHERE s.status = 'active'
      AND (
        lower(g.name || ' ' || s.name) LIKE lower(?)
        OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = s.id AND lower(cn.name) LIKE lower(?))
      )
    LIMIT $resultLimit
  ''',
  '''
    SELECT id, name AS scientific_name, 'genera' AS entity_type
    FROM genera t
    WHERE lower(t.name) LIKE lower(?)
       OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = t.id AND lower(cn.name) LIKE lower(?))
    LIMIT $resultLimit
  ''',
  '''
    SELECT id, name AS scientific_name, 'families' AS entity_type
    FROM families t
    WHERE lower(t.name) LIKE lower(?)
       OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = t.id AND lower(cn.name) LIKE lower(?))
    LIMIT $resultLimit
  ''',
  '''
    SELECT id, name AS scientific_name, 'orders' AS entity_type
    FROM orders t
    WHERE lower(t.name) LIKE lower(?)
       OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = t.id AND lower(cn.name) LIKE lower(?))
    LIMIT $resultLimit
  ''',
  '''
    SELECT id, name AS scientific_name, 'classes' AS entity_type
    FROM classes t
    WHERE lower(t.name) LIKE lower(?)
       OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = t.id AND lower(cn.name) LIKE lower(?))
    LIMIT $resultLimit
  ''',
];

/// FTS lookup against the user DB's cached runtime common names (species
/// downloaded via iNaturalist enrichment that aren't in the bundled
/// reference DB under their common name yet).
String runtimeCommonNameFtsSql(int resultLimit) => '''
  SELECT d.entity_key AS id,
         d.entity_id,
         d.entity_type,
         d.scientific_name,
         d.common_name_en,
         d.common_name_de,
         d.common_name_fr,
         d.common_name_es
  FROM runtime_common_name_search_documents d
  JOIN runtime_common_name_search_fts f ON f.rowid = d.rowid
  WHERE runtime_common_name_search_fts MATCH ?
  LIMIT $resultLimit
''';

/// `LIKE`-based fallback over the same runtime common-name documents table,
/// used when the FTS path found too few matches. Expects two bound
/// arguments: `'term%'` and `'%term%'` against `normalized_search_text`.
String runtimeCommonNameFallbackSql(String documentsTable, int resultLimit) =>
    '''
  SELECT entity_key AS id,
         entity_id,
         entity_type,
         scientific_name,
         common_name_en,
         common_name_de,
         common_name_fr,
         common_name_es
  FROM $documentsTable
  WHERE normalized_search_text LIKE ? OR normalized_search_text LIKE ?
  LIMIT $resultLimit
''';

/// Looks up reference-DB ids for a batch of normalized (trimmed, lowercased)
/// taxonomy names in [tableName] (genera/families/orders/classes). Expects
/// one bound argument per name via an `IN (?, ?, …)` placeholder list built
/// by the caller.
String taxonomyReferenceIdLookupSql(String tableName, String placeholders) =>
    '''
  SELECT id, lower(trim(name)) AS normalized_name
  FROM $tableName
  WHERE lower(trim(name)) IN ($placeholders)
  ORDER BY id
  ''';
