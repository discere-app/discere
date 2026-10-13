#!/usr/bin/env bash
# =============================================================================
# lib.sh — Helfer für die ETL-Tests (wird von run.sh gesourced)
#
# Ein Fall schlägt fehl, sobald eine Prüfung die Subshell des Falls mit
# exit 1 beendet. Prüfungen deshalb nicht in $(...) aufrufen.
# =============================================================================

fail_case() {
    echo "$*" >&2
    exit 1
}

# Führt ein Kommando aus und hält stdout, stderr und Exit-Code in OUT, ERR und
# STATUS fest, ohne dass ein Fehlschlag den Fall beendet.
run_capture() {
    set +e
    "$@" > "$TEST_TMP/stdout" 2> "$TEST_TMP/stderr"
    STATUS=$?
    set -e
    OUT="$(cat "$TEST_TMP/stdout")"
    ERR="$(cat "$TEST_TMP/stderr")"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="${3:-Wert}"
    [[ "$actual" == "$expected" ]] \
        || fail_case "$label: erwartet [$expected], erhalten [$actual]"
}

assert_status() {
    local expected="$1"
    [[ "$STATUS" -eq "$expected" ]] \
        || fail_case "Exit-Code: erwartet $expected, erhalten $STATUS"$'\n'"stdout: $OUT"$'\n'"stderr: $ERR"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]] \
        || fail_case "erwartet enthalten: [$needle]"$'\n'"in: $haystack"
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" != *"$needle"* ]] \
        || fail_case "nicht erwartet: [$needle]"$'\n'"in: $haystack"
}

# Legt ein Plugin an, das validate_plugin.sh besteht. Weitere Argumente
# werden als Zeilen an plugin.yaml angehängt.
make_plugin() {
    local plugins_dir="$1"
    local name="$2"
    shift 2
    mkdir -p "$plugins_dir/$name/sql"
    printf 'name: %s\nversion: 1\nsource: %s\n' "$name" "$name" > "$plugins_dir/$name/plugin.yaml"
    if [[ $# -gt 0 ]]; then
        printf '%s\n' "$@" >> "$plugins_dir/$name/plugin.yaml"
    fi
    : > "$plugins_dir/$name/sql/source.sql"
    printf '#!/usr/bin/env bash\n' > "$plugins_dir/$name/import.sh"
    chmod +x "$plugins_dir/$name/import.sh"
}
