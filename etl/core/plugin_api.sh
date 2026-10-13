#!/usr/bin/env bash
# =============================================================================
# plugin_api.sh — Gemeinsame Shell-API für Discere ETL Plugins
#
# Wird von plugins/*/import.sh und validate_plugin.sh gesourced.
# Stellt einen kleinen, stabilen Vertrag für Plugin-Manifeste und
# wiederverwendbare Helfer für Logging, Validierung und Source-Metadaten bereit.
# =============================================================================

# Gibt den Wert eines skalaren Feldes aus (key: value), ohne Kommentar und
# Anführungszeichen. Gesucht wird nur ein Schlüssel ohne Einrückung: Ein
# gleichnamiger verschachtelter Schlüssel (etwa unter env:) ist ein anderes
# Feld und darf kein Verhalten steuern.
plugin_manifest_get() {
    local manifest_path="$1"
    local key="$2"

    [[ -f "$manifest_path" ]] || return 1

    awk -F ':' -v key="$key" '
        $0 ~ "^" key "[[:space:]]*:" {
            sub("^" key "[[:space:]]*:[[:space:]]*", "", $0)
            sub("[[:space:]]*#.*$", "", $0)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
            gsub(/^["'\''"]|["'\''"]$/, "", $0)
            print $0
            exit
        }
    ' "$manifest_path"
}

# Gibt die Einträge einer YAML-Blockliste aus, einen pro Zeile, ohne
# Kommentare und Anführungszeichen:
#
#   depends_on_sources:
#     - fishbase   # Kommentar
#
# Gesucht wird nur ein Schlüssel ohne Einrückung. Eine leere oder fehlende
# Liste ergibt keine Ausgabe. Steht hinter dem Schlüssel ein Wert — etwa eine
# Inline-Liste wie [a, b] — oder ist ein Eintrag leer, bricht die Funktion ab:
# Mehr YAML liest sie nicht, und stilles Übergehen würde einen Eintrag
# verlieren.
plugin_manifest_list() {
    local manifest_path="$1"
    local key="$2"

    [[ -f "$manifest_path" ]] || return 1

    awk -v key="$key" '
        function strip(value) {
            sub("[[:space:]]*#.*$", "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^["'\''"]|["'\''"]$/, "", value)
            return value
        }
        !in_list && $0 ~ "^" key "[[:space:]]*:" {
            rest = $0
            sub("^" key "[[:space:]]*:", "", rest)
            if (strip(rest) != "") exit 2
            in_list = 1
            next
        }
        in_list && /^[[:space:]]*(#.*)?$/ { next }
        in_list && /^[[:space:]]*-/ {
            item = $0
            sub(/^[[:space:]]*-/, "", item)
            item = strip(item)
            if (item == "") exit 2
            print item
            next
        }
        in_list { exit }
    ' "$manifest_path" \
    || plugin_fail "$manifest_path: '$key' muss eine Blockliste mit nicht leeren Einträgen sein ('  - <wert>' je Zeile, keine Inline-Liste)."
}

plugin_log()  { echo "[$(date '+%H:%M:%S')] [${PLUGIN_SOURCE:-plugin}] $*" >&2; }
plugin_warn() { echo "[WARN] [${PLUGIN_SOURCE:-plugin}] $*" >&2; }
plugin_fail() { echo "[ERROR] [${PLUGIN_SOURCE:-plugin}] $*" >&2; exit 1; }

plugin_print_help_from_header() {
    local script_path="$1"
    local start_line="$2"
    local end_line="$3"
    sed -n "${start_line},${end_line}p" "$script_path" | sed 's/^# \{0,1\}//'
}

plugin_init() {
    local plugin_dir="$1"

    export PLUGIN_DIR="$(cd "$plugin_dir" && pwd)"
    export PLUGIN_ETL_DIR="$(cd "$PLUGIN_DIR/../.." && pwd)"
    export PLUGIN_CORE_DIR="$PLUGIN_ETL_DIR/core"
    export PLUGIN_SQL_DIR="$PLUGIN_DIR/sql"
    export PLUGIN_MANIFEST_PATH="$PLUGIN_DIR/plugin.yaml"

    [[ -f "$PLUGIN_MANIFEST_PATH" ]] || plugin_fail "plugin.yaml fehlt: $PLUGIN_MANIFEST_PATH"

    export PLUGIN_NAME="$(plugin_manifest_get "$PLUGIN_MANIFEST_PATH" "name")"
    export PLUGIN_SOURCE="$(plugin_manifest_get "$PLUGIN_MANIFEST_PATH" "source")"
    export PLUGIN_MANIFEST_VERSION="$(plugin_manifest_get "$PLUGIN_MANIFEST_PATH" "version")"

    [[ -n "${PLUGIN_NAME:-}" ]] || plugin_fail "Pflichtfeld 'name' fehlt in plugin.yaml"
    [[ -n "${PLUGIN_SOURCE:-}" ]] || plugin_fail "Pflichtfeld 'source' fehlt in plugin.yaml"
    [[ -n "${PLUGIN_MANIFEST_VERSION:-}" ]] || plugin_fail "Pflichtfeld 'version' fehlt in plugin.yaml"
}

plugin_require_db_path() {
    local db_path="$1"
    [[ -n "$db_path" ]] || plugin_fail "--db ist ein Pflichtfeld."
    [[ -f "$db_path" ]] || plugin_fail "Datenbank nicht gefunden: $db_path"
}

plugin_require_command() {
    local command_name
    for command_name in "$@"; do
        command -v "$command_name" >/dev/null 2>&1 \
            || plugin_fail "$command_name nicht gefunden."
    done
}

plugin_cleanup_dir() {
    local path="${1:-}"
    [[ -n "$path" ]] && rm -rf "$path"
}

plugin_write_source_metadata() {
    local db_path="$1"
    local source_sql_path="$2"
    local source_version="$3"
    local now

    [[ -f "$source_sql_path" ]] || plugin_fail "source.sql fehlt: $source_sql_path"

    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    plugin_log "Schreibe Quellenangabe für '${PLUGIN_SOURCE}'..."
    sed -e "s|\${VERSION}|$source_version|g" \
        -e "s|\${NOW}|$now|g" \
        "$source_sql_path" \
    | sqlite3 "$db_path" \
    || plugin_fail "source.sql fehlgeschlagen."

    sqlite3 "$db_path" \
        "INSERT INTO metadata (key, value) VALUES ('${PLUGIN_SOURCE}', '$source_version')
         ON CONFLICT (key) DO UPDATE SET value = excluded.value;" \
    || plugin_fail "metadata-Eintrag fehlgeschlagen."

    plugin_log "Quellenangabe geschrieben (version=$source_version)."
}

plugin_validate_source_entry_exists() {
    local db_path="$1"
    local source_count

    source_count=$(sqlite3 "$db_path" \
        "SELECT COUNT(*) FROM sources WHERE id='${PLUGIN_SOURCE}';")
    [[ "$source_count" -eq 1 ]] \
        || plugin_fail "Kein sources-Eintrag für '${PLUGIN_SOURCE}'."
}

# Build-Bericht: hält fest, was eine Quelle nicht zuordnen konnte, ohne den
# Build abzubrechen (fehlende oder mehrdeutige Zuordnungen externer Quellen).
#
# Liest Einträge von stdin, je Zeile tabgetrennt Kategorie, Schlüssel, Name
# und Detail, und hängt sie mit der Quelle als erster Spalte an
# $DISCERE_REPORT_DIR/<quelle>.tsv an. build.sh legt das Verzeichnis je Build
# neu an. Ohne DISCERE_REPORT_DIR — ein Plugin läuft von Hand — werden die
# Einträge nur gezählt: Ein Bericht neben einer beliebigen DB wäre von keinem
# Build und würde beim nächsten Lauf mit fremden Einträgen vermischt.
plugin_report() {
    local report_file count

    if [[ -z "${DISCERE_REPORT_DIR:-}" ]]; then
        count="$(grep -c . || true)"
        if [[ "$count" -gt 0 ]]; then
            plugin_warn "Kein Build-Bericht (DISCERE_REPORT_DIR nicht gesetzt): $count Einträge nicht festgehalten."
        fi
        return 0
    fi

    mkdir -p "$DISCERE_REPORT_DIR"
    report_file="$DISCERE_REPORT_DIR/${PLUGIN_SOURCE}.tsv"
    if [[ ! -f "$report_file" ]]; then
        printf 'source\tcategory\tkey\tname\tdetail\n' > "$report_file"
    fi
    awk -v source="$PLUGIN_SOURCE" 'NF { print source "\t" $0 }' >> "$report_file"
}

plugin_validate_min_count() {
    local db_path="$1"
    local table_name="$2"
    local where_clause="$3"
    local min_count="$4"
    local label="$5"
    local count

    count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM ${table_name} WHERE ${where_clause};")
    [[ "$count" -ge "$min_count" ]] \
        || plugin_fail "Zu wenige ${label}: $count (erwartet >= $min_count)"
}
