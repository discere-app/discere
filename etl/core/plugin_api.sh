#!/usr/bin/env bash
# =============================================================================
# plugin_api.sh — Gemeinsame Shell-API für Discere ETL Plugins
#
# Wird von plugins/*/import.sh und validate_plugin.sh gesourced.
# Stellt einen kleinen, stabilen Vertrag für Plugin-Manifeste, den Parser der
# Aufruf-Schnittstelle (plugin_parse_args, beschrieben in
# docs/plugin-interface.md) und wiederverwendbare Helfer für Logging,
# Validierung und Source-Metadaten bereit.
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

# Gibt den Kopfkommentar eines Scripts als Hilfe aus: alles zwischen der
# ersten und der zweiten Linie aus '# ===…'.
plugin_print_help() {
    awk '/^# =+$/ { if (++rules == 2) exit; next } rules == 1' "$1" | sed 's/^# \{0,1\}//'
}

# plugin_parse_args [<flag>=<VARIABLE> …] -- "$@"
#
# Liest die Aufruf-Schnittstelle eines Plugins (docs/plugin-interface.md):
# die gemeinsamen Flags --db, --no-download, --keep und --help, dazu die
# eigenen Flags des Plugins, je eines mit Wert, das <VARIABLE> setzt — etwa
# --data-dir=EXAMPLE_DATA_DIR. Setzt DB_PATH (Vorgabe: die gleichnamige
# Umgebungsvariable), DOWNLOAD (true, mit --no-download false) und
# KEEP_FILES (mit --keep true). Ein unbekanntes Flag oder eines ohne Wert
# bricht ab: Ein Tippfehler wie --no-dowload würde sonst still laden und
# danach löschen.
plugin_parse_args() {
    local specs=() spec matched

    while [[ $# -gt 0 && "$1" != -- ]]; do
        specs+=("$1")
        shift
    done
    [[ $# -gt 0 ]] || plugin_fail "plugin_parse_args: '--' vor den Argumenten fehlt."
    shift

    DB_PATH="${DB_PATH:-}"
    DOWNLOAD=true
    KEEP_FILES=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --db)
                [[ $# -ge 2 ]] || plugin_fail "--db braucht einen Wert."
                DB_PATH="$2"
                shift
                ;;
            --no-download) DOWNLOAD=false ;;
            --keep)        KEEP_FILES=true ;;
            --help|-h)
                plugin_print_help "$0"
                exit 0
                ;;
            *)
                matched=false
                for spec in ${specs[@]+"${specs[@]}"}; do
                    [[ "$1" == "${spec%%=*}" ]] || continue
                    [[ $# -ge 2 ]] || plugin_fail "$1 braucht einen Wert."
                    printf -v "${spec#*=}" '%s' "$2"
                    matched=true
                    shift
                    break
                done
                [[ "$matched" == true ]] \
                    || plugin_fail "Unbekanntes Argument: $1 (siehe --help)"
                ;;
        esac
        shift
    done
}

# plugin_skip_download_for_local_path <pfad>
# Ein ausdrücklich angegebener lokaler Pfad (eigenes Flag oder
# Umgebungsvariable) gehört dem Nutzer: Das Plugin liest ihn nur, lädt nichts
# und löscht nichts. Ist <pfad> nicht leer, setzt die Funktion deshalb
# DOWNLOAD=false — ein Plugin löscht nur, was es selbst in seinen Cache
# geladen hat. Aufruf nach plugin_parse_args.
plugin_skip_download_for_local_path() {
    if [[ -n "$1" ]]; then
        DOWNLOAD=false
    fi
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

# Gibt <sql-datei> aus und ersetzt jede Zeile „-- @include <name>“ durch den
# Inhalt von $PLUGIN_CORE_DIR/sql/<name>. So teilen Plugins Regeln, die für
# mehrere Quellen gleich gelten (core/sql/source_codes.sql), statt sie zu
# kopieren. Fehlt die Datei, bricht die Funktion ab.
plugin_render_sql() {
    awk -v dir="$PLUGIN_CORE_DIR/sql" '
        /^-- @include / {
            file = dir "/" $3
            while ((status = (getline line < file)) > 0) print line
            if (status < 0) { print "Include nicht gefunden: " file > "/dev/stderr"; exit 1 }
            close(file)
            next
        }
        { print }
    ' "$1"
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

# version_at_least <version> <mindestens>
# Vergleicht Versionsnummern der Form x.y.z Teil für Teil als Zahlen;
# fehlende Teile zählen als 0.
version_at_least() {
    local have need i
    IFS=. read -r -a have <<< "$1"
    IFS=. read -r -a need <<< "$2"
    for i in 0 1 2; do
        if (( 10#${have[$i]:-0} > 10#${need[$i]:-0} )); then
            return 0
        fi
        if (( 10#${have[$i]:-0} < 10#${need[$i]:-0} )); then
            return 1
        fi
    done
    return 0
}

# Die Identitäts-Stage bricht über RAISE(ABORT, <Ausdruck>) ab; einen
# Ausdruck statt eines festen Texts nimmt RAISE erst ab sqlite 3.47.
SQLITE_MIN_VERSION="3.47.0"

plugin_require_sqlite_version() {
    local version
    plugin_require_command sqlite3
    version="$(sqlite3 --version | awk '{ print $1 }')"
    if ! version_at_least "$version" "$SQLITE_MIN_VERSION"; then
        plugin_fail "sqlite3 $version ist zu alt, gebraucht wird mindestens $SQLITE_MIN_VERSION ($(command -v sqlite3))."
    fi
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

# Bericht von core/sql/source_codes.sql (code_report.tsv eines Exports) in
# den Build-Bericht, mit Zählung im Log.
plugin_report_source_codes() {
    local report="$1"
    plugin_report < "$report"
    plugin_log "Doppelte Codes: $(grep -c '^code_duplicate' "$report" || true) Zeilen," \
        "Familien darunter mit Ordnung: $(grep -c '^family_order_resolved' "$report" || true)," \
        "ohne: $(grep -c '^family_order_rejected' "$report" || true)"
}

# Bericht von core/sql/distribution_regions.sql (distribution_report.tsv
# eines Exports) in den Build-Bericht, mit Zählung im Log.
plugin_report_distribution() {
    local report="$1"
    plugin_report < "$report"
    plugin_log "Verbreitung zusammengefasst: $(grep -c '^distribution_status_merged' "$report" || true)" \
        "Schlüssel mit verschiedenem Status, $(grep -c '^distribution_rows_merged' "$report" || true) mit gleichem;" \
        "unbekannter Status: $(grep -c '^distribution_status_unknown' "$report" || true) Schlüssel"
}

# Zählung von core/sql/common_names.sql (common_names_summary.tsv eines
# Exports) ins Log. Die Schlüssel selbst kommen nicht in den Build-Bericht:
# Es sind einige tausend je Quelle, zusammengefasst nach fester Regel und so,
# dass die App dasselbe zeigt — einzeln aufgeführt wären sie kein Signal.
plugin_log_common_names() {
    local summary="$1"
    plugin_log "Volksnamen zusammengefasst: $(plugin_summary_count "$summary" common_names_merged) Schlüssel," \
        "davon $(plugin_summary_count "$summary" common_names_preferred_over_rank) bevorzugt vor niedrigerem Rang," \
        "$(plugin_summary_count "$summary" common_names_global) ohne Land"
}

# Anzahl zur <kategorie> aus einer Zählung (je Zeile Kategorie und Anzahl,
# tabgetrennt).
plugin_summary_count() {
    awk -F '\t' -v category="$2" '$1 == category { print $2 }' "$1"
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
