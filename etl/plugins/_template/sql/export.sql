-- =============================================================================
-- <Plugin-Name> Export — eine einzige DuckDB-Session
--
-- Alle IDs über discere_uuid() erzeugen — nie selbst konstruieren.
-- Parents zuerst laden; Children joinen auf diese für FK-Auflösung.
--
-- UUID-Format: discere:<source>_<entity>:<external_id>
-- Beispiel:    discere:example_species:42
-- =============================================================================

-- Zentraler ID-Generator — nicht umgehen.
CREATE OR REPLACE MACRO discere_uuid(source, entity, external_id) AS
    'discere:' || source || '_' || entity || ':' || CAST(external_id AS VARCHAR);

-- ---------------------------------------------------------------------------
-- Beispiel: Species
-- Reihenfolge: classes → orders → families → genera → species → pictures
-- ---------------------------------------------------------------------------
-- CREATE TEMP TABLE t_species AS
-- SELECT
--     discere_uuid('example', 'species', s.id)  AS id,
--     CAST(s.id AS VARCHAR)                      AS external_id,
--     'example'                                  AS external_source,
--     s.name                                     AS name,
--     -- ...weitere Felder
-- FROM read_parquet('${DATA_DIR}/species.parquet') s;
--
-- COPY t_species TO '${EXPORT_DIR}/species.csv' (FORMAT csv, HEADER true);
