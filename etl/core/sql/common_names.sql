-- =============================================================================
-- common_names.sql — Volksnamen einer Quelle im FishBase-Format (DuckDB)
--
-- Eingebunden von plugins/fishbase und plugins/sealifebase an der Zeile
-- „-- @include common_names.sql“ ihrer export.sql (plugin_render_sql in
-- core/plugin_api.sh), nach t_common_name_rows: alle Volksnamen der Quelle,
-- Arten wie höhere Taxa, mit den Spalten von common_names (entity_id,
-- entity_type, language, country, name, source, rank, is_preferred,
-- name_type).
--
-- Ein Schlüssel ist ein Name einer Entität in einer Sprache und einem Land
-- (entity_id, name, language, source, country), der Schlüssel des Index
-- idx_common_names_key in core/sql/schema.sql. country NULL (C_Code 9999,
-- global) zählt dabei als ein eigenes Land. Die Quelle führt einen Namen im
-- selben Land teils mehrmals, mit anderem Rang, Vorzug oder Namenstyp (FAO
-- neben Vernacular). Die Datenbank hält je Schlüssel eine Zeile: die, die die
-- App unter den Zeilen des Schlüssels zuerst liest — bevorzugt vor Rang
-- (lib/catalog/repository/common_name_repository.dart), ohne Rang vor jedem
-- Rang, weil SQLite NULL aufsteigend zuerst sortiert. So zeigt die App
-- dasselbe, als stünden alle Zeilen da; eine Zusammenfassung wie
-- MAX(is_preferred), MIN(rank) verschöbe dagegen die Sortierung. Unter Zeilen
-- gleichen Vorzugs und Rangs entscheiden der Namenstyp und zuletzt
-- entity_type, damit das Ergebnis nicht von der Reihenfolge der Eingabe
-- abhängt:
--
--   is_preferred DESC, rank ASC NULLS FIRST, name_type ASC NULLS LAST,
--   entity_type ASC
--
-- Dieselbe Regel wählt die Volksnamen, die core/identity.sh aus dem
-- Vorgänger übernimmt (carried_common_names_sql). Wer sie ändert, ändert
-- beide.
--
-- Ergebnis:
--   common_names.csv         — je Schlüssel eine Zeile
--   common_names_summary.tsv — Zählung für das Log (plugin_log_common_names
--                              in core/plugin_api.sh), je Zeile Kategorie
--                              und Anzahl Schlüssel:
--     common_names_merged              Schlüssel mit mehreren Zeilen
--     common_names_preferred_over_rank davon gewählt die bevorzugte Zeile
--                                      vor einer, die nach Rang allein
--                                      vorn stünde
--     common_names_global              davon ohne Land
-- =============================================================================

CREATE TEMP TABLE t_common_names AS
SELECT
    *,
    COUNT(*) OVER common_name_key                                       AS key_row_count,
    FIRST_VALUE(rank) OVER (common_name_key ORDER BY rank ASC NULLS FIRST) AS key_first_rank
FROM t_common_name_rows
WINDOW common_name_key AS (PARTITION BY entity_id, name, language, source, country)
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY entity_id, name, language, source, country
    ORDER BY COALESCE(is_preferred, 0) DESC, rank ASC NULLS FIRST,
             name_type ASC NULLS LAST, entity_type ASC
) = 1;

-- Je Schlüssel eine Zeile, sortiert nach dem Schlüssel: Die Datei ist bei
-- gleicher Quelle byte-gleich.
COPY (
    SELECT entity_id, entity_type, language, country, name, source, rank, is_preferred, name_type
    FROM t_common_names
    ORDER BY entity_type, entity_id, language, country, name, source
)
TO '${EXPORT_DIR}/common_names.csv' (FORMAT csv, HEADER true);

COPY (
    SELECT 'common_names_merged', COUNT(*)
    FROM t_common_names WHERE key_row_count > 1
    UNION ALL
    SELECT 'common_names_preferred_over_rank', COUNT(*)
    FROM t_common_names WHERE key_row_count > 1 AND rank IS DISTINCT FROM key_first_rank
    UNION ALL
    SELECT 'common_names_global', COUNT(*)
    FROM t_common_names WHERE key_row_count > 1 AND country IS NULL
)
TO '${EXPORT_DIR}/common_names_summary.tsv' (FORMAT csv, DELIMITER '\t', HEADER false, QUOTE '');
