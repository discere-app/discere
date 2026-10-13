#!/usr/bin/env bash
# =============================================================================
# run.sh — Tests für das ETL
#
# Usage:
#   ./tests/run.sh
#
# Läuft unter Bash 3.2, braucht nur sqlite3 und kein Netzwerk. Jede Funktion
# test_* aus tests/test_*.sh läuft in einer eigenen Subshell mit eigenem
# Temp-Verzeichnis ($TEST_TMP). Gibt je Fall eine Zeile aus, bei einem
# Fehlschlag zusätzlich dessen Ausgabe, und endet mit Exit-Code 1, sobald ein
# Fall fehlschlägt.
# =============================================================================

set -Euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETL_DIR="$(cd "$TESTS_DIR/.." && pwd)"

# shellcheck source=./lib.sh
source "$TESTS_DIR/lib.sh"

passed=0
failed=0

run_test() {
    local test_name="$1"
    local log_file status
    TEST_TMP="$(mktemp -d)"
    log_file="$TEST_TMP/test.log"
    ( set -e; "$test_name" ) > "$log_file" 2>&1
    status=$?
    if [[ $status -eq 0 ]]; then
        echo "ok   $test_name"
        passed=$((passed + 1))
    else
        echo "FAIL $test_name"
        sed 's/^/     | /' "$log_file"
        failed=$((failed + 1))
    fi
    rm -rf "$TEST_TMP"
}

# Fälle in der Reihenfolge, in der sie in ihrer Datei stehen.
for test_file in "$TESTS_DIR"/test_*.sh; do
    # shellcheck source=/dev/null
    source "$test_file"
    for test_name in $(sed -n 's/^\(test_[A-Za-z0-9_]*\)() {$/\1/p' "$test_file"); do
        run_test "$test_name"
    done
done

echo "$passed bestanden, $failed fehlgeschlagen"
[[ $failed -eq 0 ]]
