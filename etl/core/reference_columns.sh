#!/usr/bin/env bash
# =============================================================================
# reference_columns.sh — Welche Spalten der Referenz-DB auf Entitäten zeigen
#
# Wird von core/identity.sh (umschreiben) und core/check_references.sh
# (prüfen) gesourced, damit beide dieselben Spalten kennen.
# =============================================================================

ENTITY_TABLES=(species genera families orders classes)

# Spalten ohne Fremdschlüssel, die auf Entitäten verweisen. Die übrigen
# Verweise ergeben sich aus den Fremdschlüsseln des Schemas; eine neue
# Spalte dieser Art gehört hierher, sonst behält sie vorläufige IDs.
# entity_external_ids führt bei höheren Taxa Namensschlüssel (genus:barbus),
# die keine ID sind und unverändert bleiben.
REFERENCE_COLUMNS_WITHOUT_FK=(
    "common_names entity_id"
    "taxonomy_traits entity_id"
    "taxonomy_distribution_regions entity_id"
    "entity_external_ids entity_id"
)

# foreign_key_columns <db>
# Je Zeile „Tabelle Spalte“: Fremdschlüssel, die auf eine Entitätstabelle
# zeigen.
foreign_key_columns() {
    sqlite3 -separator ' ' "$1" "
        SELECT m.name, f.\"from\"
        FROM sqlite_schema m
        JOIN pragma_foreign_key_list(m.name) f
        WHERE m.type = 'table'
          AND f.\"table\" IN ('species', 'genera', 'families', 'orders', 'classes')
        ORDER BY m.name, f.\"from\";"
}

# reference_columns <db>
# Je Zeile „Tabelle Spalte“: alle Spalten, die eine Entitäts-ID tragen — die
# IDs der Entitätstabellen, die Fremdschlüssel und die Liste oben.
reference_columns() {
    local table
    for table in "${ENTITY_TABLES[@]}"; do
        echo "$table id"
    done
    foreign_key_columns "$1"
    printf '%s\n' "${REFERENCE_COLUMNS_WITHOUT_FK[@]}"
}
