#!/usr/bin/env bash
# =============================================================================
# identity.sh — Identitäts-Stage: endgültige IDs aus dem ID-Register
#
# Usage:
#   ./core/identity.sh --db <db> --plugins-dir <dir> --previous-release <db>
#   ./core/identity.sh --db <db> --plugins-dir <dir> --initial
#
# Läuft nach den Quellen mit Entitäten und vor den ergänzenden (build.sh,
# Stage 02b). Die Quellen mit Entitäten schreiben vorläufige IDs (discere:<quelle>_<typ>:<external_id>); diese Stage ersetzt
# sie in der ganzen DB durch die endgültigen (discere:<typ>:<nr>) und schreibt
# Register (entity_source_keys) und Aliase (entity_aliases). Regeln:
# docs/datenquellen.md, Identität und Lebenszyklus.
#
#   1. Register aus dem vorigen Release übernehmen — oder, wenn es noch keins
#      führt, einmalig aus seinen IDs ableiten (identity_register_*.sql).
#   2. Jede Zeile der Entitätstabellen über ihren Schlüssel (Quelle, Typ,
#      external_id) zuordnen: bekannter Schlüssel → registrierte ID; Art mit
#      unbekanntem Schlüssel → Abgleich gegen die Arten anderer Quellen, je
#      Quelle nach placement_priority; sonst neue ID (identity_assign.sql,
#      identity_match.sql, identity_number.sql).
#   3. Umschreiben: jede Spalte, die auf eine Entität verweist, bekommt die
#      endgültige ID. Gehen zwei Zeilen in einer Art auf, bleibt die der
#      gewichtigeren Quelle; Beiträge der anderen werden umgehängt.
#   4. Entitäten des Vorgängers, die keine Quelle mehr geliefert hat, aus dem
#      Vorgänger übernehmen (Arten deprecated), samt Namen.
#   5. Register und Aliase schreiben, Invarianten prüfen (identity_finish.sql).
#
# --initial baut ohne Vorgänger und vergibt alle IDs neu ab 1 — nur für Tests
# und einen allerersten Build: Die Lernstände der Nutzer zeigten danach ins
# Leere.
#
# Build-Bericht (Quelle „identity“): ambiguous — eine neue Art trifft mehrere
# Arten anderer Quellen; placement — eine zusammengeführte Art hat bei der
# weniger gewichtigen Quelle eine andere Einordnung.
# =============================================================================

set -Eeuo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$CORE_DIR/sql"

# shellcheck source=./plugin_api.sh
source "$CORE_DIR/plugin_api.sh"
# shellcheck source=./reference_columns.sh
source "$CORE_DIR/reference_columns.sh"
PLUGIN_SOURCE="identity"

DB_PATH=""
PLUGINS_DIR=""
PREVIOUS_DB=""
INITIAL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)               DB_PATH="$2"; shift ;;
        --plugins-dir)      PLUGINS_DIR="$2"; shift ;;
        --previous-release) PREVIOUS_DB="$2"; shift ;;
        --initial)          INITIAL=true ;;
        --help|-h)
            plugin_print_help_from_header "$0" 2 35
            exit 0
            ;;
        *) plugin_fail "Unbekanntes Argument: $1" ;;
    esac
    shift
done

plugin_require_sqlite_version
plugin_require_db_path "$DB_PATH"
[[ -d "$PLUGINS_DIR" ]] || plugin_fail "Plugin-Verzeichnis nicht gefunden: '$PLUGINS_DIR' (--plugins-dir)."
if [[ "$INITIAL" == true && -n "$PREVIOUS_DB" ]]; then
    plugin_fail "--initial und --previous-release schließen sich aus."
fi
if [[ "$INITIAL" == false && -z "$PREVIOUS_DB" ]]; then
    plugin_fail "Kein Vorgänger: --previous-release <db> oder ausdrücklich --initial."
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------------------------------------------------------------------------
# Quellen und Rang
# ---------------------------------------------------------------------------

# Jede Quelle, die Entitäten liefert, braucht eine placement_priority: Sie
# entscheidet, welche Zeile gilt, wenn zwei Quellen dieselbe Art liefern.
sources_sql() {
    local sources source priority seen_priorities=" "
    sources="$(sqlite3 "$DB_PATH" "
        SELECT external_source FROM species
        UNION SELECT external_source FROM genera
        UNION SELECT external_source FROM families
        UNION SELECT external_source FROM orders
        UNION SELECT external_source FROM classes
        ORDER BY 1;")"
    [[ -n "$sources" ]] || plugin_fail "Keine Entitäten in $DB_PATH."

    echo "CREATE TEMP TABLE identity_sources (source TEXT NOT NULL PRIMARY KEY, priority INTEGER NOT NULL);"
    for source in $sources; do
        priority="$(plugin_manifest_get "$PLUGINS_DIR/$source/plugin.yaml" "placement_priority" || true)"
        [[ -n "$priority" ]] \
            || plugin_fail "Quelle '$source' liefert Entitäten, hat aber keine placement_priority in $PLUGINS_DIR/$source/plugin.yaml."
        [[ "$priority" =~ ^-?[0-9]+$ ]] \
            || plugin_fail "Quelle '$source': placement_priority '$priority' ist keine ganze Zahl."
        [[ "$seen_priorities" != *" $priority "* ]] \
            || plugin_fail "Zwei Quellen mit placement_priority $priority."
        seen_priorities="$seen_priorities$priority "
        echo "INSERT INTO identity_sources VALUES ('$source', $priority);"
    done
}

sources_by_priority() {
    sqlite3 "$DB_PATH" "$(sources_sql) SELECT source FROM identity_sources ORDER BY priority;"
}

# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

table_columns() {
    sqlite3 "$1" "SELECT name FROM pragma_table_info('$2') ORDER BY cid;"
}

has_table() {
    [[ "$(sqlite3 "$1" "SELECT COUNT(*) FROM sqlite_schema WHERE type = 'table' AND name = '$2';")" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Generiertes SQL
# ---------------------------------------------------------------------------

# Beiträge, deren Entität keine Quelle geliefert hat (FishBase führt etwa
# Verbreitungsdaten zu SpecCodes ohne Art), haben keine ID, auf die sie
# umgeschrieben werden könnten, und sind in der App nicht erreichbar. Sie
# entfallen; die Zahl steht im Log.
orphan_contributions_sql() {
    local entry table column
    for entry in "${REFERENCE_COLUMNS_WITHOUT_FK[@]}"; do
        table="${entry% *}"
        column="${entry#* }"
        cat << SQL
INSERT INTO identity_counts (label, n)
SELECT 'Beiträge ohne Entität entfernt: $table', COUNT(*) FROM "$table"
WHERE "$column" GLOB 'discere:*' AND "$column" NOT IN (SELECT provisional_id FROM identity_id_map);
DELETE FROM "$table"
WHERE "$column" GLOB 'discere:*' AND "$column" NOT IN (SELECT provisional_id FROM identity_id_map);
SQL
    done
}

# Ein leerer Verweis ('' aus dem CSV-Import der Plugins) ist kein Verweis.
empty_references_sql() {
    local table column
    while read -r table column; do
        cat << SQL
INSERT INTO identity_counts (label, n)
SELECT 'leere Verweise zu NULL: $table.$column', COUNT(*) FROM "$table" WHERE "$column" = '';
UPDATE "$table" SET "$column" = NULL WHERE "$column" = '';
SQL
    done < <(foreign_key_columns "$DB_PATH")
}

# Erst die Zeilen der gültigen Quelle, dann die übrigen mit OR IGNORE: Wo
# eine Zeile der weniger gewichtigen Quelle mit einem Schlüssel kollidiert
# (UNIQUE, PRIMARY KEY), behält die gewichtigere ihren Beitrag — in den
# Entitätstabellen ist das die Zeile der Entität selbst — und die übrige
# Zeile entfällt.
rewrite_sql() {
    local table column
    while read -r table column; do
        cat << SQL
UPDATE OR IGNORE "$table" SET "$column" = m.entity_id
FROM identity_id_map m WHERE m.provisional_id = "$table"."$column" AND m.is_winner = 1;
UPDATE OR IGNORE "$table" SET "$column" = m.entity_id
FROM identity_id_map m WHERE m.provisional_id = "$table"."$column" AND m.is_winner = 0;
DELETE FROM "$table"
WHERE "$column" IN (SELECT provisional_id FROM identity_id_map WHERE is_winner = 0);
SQL
    done < <(reference_columns "$DB_PATH")
}

# Übernimmt die Zeilen von <tabelle> aus dem Vorgänger, deren <verknüpfung>
# auf eine übernommene Entität zeigt. Spalten, die beide Schemata kennen;
# Verweise auf Entitäten werden auf deren ID in diesem Build abgebildet.
carry_over_sql() {
    local table="$1" link_column="$2"
    local column columns="" expressions="" expression prev_columns fk_columns
    prev_columns="$(table_columns "$PREVIOUS_DB" "$table")"
    fk_columns="$(foreign_key_columns "$DB_PATH" | awk -v t="$table" '$1 == t { print $2 }')"

    for column in $(table_columns "$DB_PATH" "$table"); do
        if [[ "$table" == species && ( "$column" == status || "$column" == deprecated_at ) ]]; then
            continue
        fi
        if ! grep -qxF "$column" <<< "$prev_columns"; then
            continue
        fi
        if [[ "$column" == "$link_column" ]]; then
            expression="c.entity_id"
        elif grep -qxF "$column" <<< "$fk_columns"; then
            expression="(SELECT entity_id FROM identity_prev_ids WHERE prev_id = p.\"$column\")"
        else
            expression="p.\"$column\""
        fi
        columns="$columns, \"$column\""
        expressions="$expressions, $expression"
    done
    if [[ "$table" == species ]]; then
        columns="$columns, status, deprecated_at"
        expressions="$expressions, 'deprecated', COALESCE(p.deprecated_at, CAST(strftime('%s', 'now') AS INTEGER))"
    fi

    cat << SQL
INSERT INTO main."$table" (${columns#, })
SELECT ${expressions#, }
FROM prev."$table" p
JOIN identity_carried c ON c.prev_id = p."$link_column";
SQL
}

# Nach dem Umschreiben darf keine Verweisspalte mehr eine vorläufige ID
# dieses Builds oder eine abgelöste ID des Vorgängers tragen.
leftover_ids_sql() {
    local table column
    while read -r table column; do
        cat << SQL
INSERT INTO identity_failure (message)
SELECT '$table.$column: ' || COUNT(*) || ' vorläufige oder abgelöste IDs, z. B. ' || MIN("$column")
FROM "$table"
WHERE "$column" IN (SELECT provisional_id FROM identity_id_map)
   OR "$column" IN (SELECT prev_id FROM identity_prev_ids WHERE prev_id != entity_id)
HAVING COUNT(*) > 0;
SQL
    done < <(reference_columns "$DB_PATH")
}

# Pfad als nur lesbare SQLite-URI in einem SQL-String.
read_only_uri() {
    local path
    path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    path="$(printf '%s' "$path" | sed -e 's/%/%25/g' -e 's/?/%3f/g' -e 's/#/%23/g' -e "s/'/''/g")"
    echo "file:$path?mode=ro"
}

# Ersetzt Zeilenumbrüche und Tabs, damit jeder Eintrag eine TSV-Zeile bleibt.
tsv_clean() {
    echo "replace(replace(replace($1, char(9), ' '), char(10), ' '), char(13), ' ')"
}

identity_script() {
    local source table

    echo ".bail on"
    echo "PRAGMA foreign_keys = OFF;"
    if [[ "$INITIAL" == false ]]; then
        echo "ATTACH '$(read_only_uri "$PREVIOUS_DB")' AS prev;"
    fi
    sources_sql
    echo "CREATE TEMP TABLE identity_counts (label TEXT NOT NULL, n INTEGER NOT NULL);"
    echo "BEGIN;"
    echo ".read \"$SQL_DIR/identity_register.sql\""
    if [[ "$INITIAL" == false ]]; then
        if has_table "$PREVIOUS_DB" entity_source_keys; then
            echo ".read \"$SQL_DIR/identity_register_load.sql\""
        else
            echo ".read \"$SQL_DIR/identity_register_derive.sql\""
        fi
        if has_table "$PREVIOUS_DB" entity_aliases; then
            echo "INSERT INTO identity_prev_aliases (alias_id, entity_id) SELECT alias_id, entity_id FROM prev.entity_aliases;"
        fi
    fi
    echo ".read \"$SQL_DIR/identity_assign.sql\""

    sed "s|\${MATCH_SQL}|$SQL_DIR/match.sql|g" "$SQL_DIR/identity_match.sql" > "$WORK_DIR/identity_match.sql"
    for source in $(sources_by_priority); do
        echo "DELETE FROM identity_current_source;"
        echo "INSERT INTO identity_current_source VALUES ('$source');"
        echo ".read \"$WORK_DIR/identity_match.sql\""
    done

    echo ".read \"$SQL_DIR/identity_number.sql\""
    orphan_contributions_sql
    empty_references_sql
    rewrite_sql
    if [[ "$INITIAL" == false ]]; then
        for table in "${ENTITY_TABLES[@]}"; do
            carry_over_sql "$table" id
        done
        carry_over_sql species_scientific_names species_id
        carry_over_sql common_names entity_id
    fi
    echo ".read \"$SQL_DIR/identity_finish.sql\""
    leftover_ids_sql
    echo "COMMIT;"

    cat << SQL
.mode list
.separator "\t"
.once "$WORK_DIR/report.tsv"
SELECT $(tsv_clean category), $(tsv_clean key), $(tsv_clean name), $(tsv_clean detail)
FROM identity_report ORDER BY category, key;
.output "$WORK_DIR/summary.txt"
.read "$SQL_DIR/identity_summary.sql"
.output stdout
SQL
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [[ "$INITIAL" == true ]]; then
    plugin_warn "--initial: ohne Vorgänger, alle IDs werden neu vergeben. Nur für Tests und einen allerersten Build."
else
    [[ -f "$PREVIOUS_DB" ]] || plugin_fail "Vorgänger nicht gefunden: $PREVIOUS_DB"
    for table in "${ENTITY_TABLES[@]}"; do
        has_table "$PREVIOUS_DB" "$table" || plugin_fail "Vorgänger $PREVIOUS_DB hat keine Tabelle $table."
    done
    if has_table "$PREVIOUS_DB" entity_source_keys; then
        plugin_log "Vorgänger: $PREVIOUS_DB (mit Register)"
    else
        plugin_log "Vorgänger: $PREVIOUS_DB (ohne Register — wird einmalig aus seinen IDs abgeleitet)"
    fi
fi

identity_script > "$WORK_DIR/identity.sql"
sqlite3 "$DB_PATH" < "$WORK_DIR/identity.sql" \
    || plugin_fail "Identitäts-Stage fehlgeschlagen — DB wird nicht verwendet."

plugin_report < "$WORK_DIR/report.tsv"
while IFS= read -r line; do
    plugin_log "$line"
done < "$WORK_DIR/summary.txt"
