#!/usr/bin/env bash
# Tests für plugin_manifest_list aus core/plugin_api.sh

# plugin_fail beendet die Shell, in der es läuft — deshalb eine Subshell.
manifest_list() {
    ( source "$ETL_DIR/core/plugin_api.sh"; plugin_manifest_list "$@" )
}

write_manifest() {
    printf '%s\n' "$@" > "$TEST_TMP/plugin.yaml"
}

test_manifest_list_reads_block_list_without_comments_and_quotes() {
    write_manifest \
        'name: x' \
        'requires:' \
        '  # nur Werkzeuge' \
        '  - duckdb' \
        '' \
        '  - "sqlite3"   # Kommentar' \
        "  - 'curl'" \
        'flags:' \
        '  - --db <path>'
    run_capture manifest_list "$TEST_TMP/plugin.yaml" requires
    assert_status 0
    assert_eq "duckdb"$'\n'"sqlite3"$'\n'"curl" "$OUT" "Einträge"
}

test_manifest_list_ignores_indented_key_of_same_name() {
    write_manifest \
        'env:' \
        '  requires:' \
        '    - nested' \
        'requires:' \
        '  - sqlite3'
    run_capture manifest_list "$TEST_TMP/plugin.yaml" requires
    assert_status 0
    assert_eq "sqlite3" "$OUT" "Einträge"
}

test_manifest_list_prints_nothing_for_empty_list() {
    write_manifest 'depends_on_sources:' 'version: 1'
    run_capture manifest_list "$TEST_TMP/plugin.yaml" depends_on_sources
    assert_status 0
    assert_eq "" "$OUT" "Ausgabe"
}

test_manifest_list_prints_nothing_for_missing_list() {
    write_manifest 'name: x'
    run_capture manifest_list "$TEST_TMP/plugin.yaml" depends_on_sources
    assert_status 0
    assert_eq "" "$OUT" "Ausgabe"
}

test_manifest_list_rejects_inline_list() {
    write_manifest 'depends_on_sources: [fishbase, sealifebase]'
    run_capture manifest_list "$TEST_TMP/plugin.yaml" depends_on_sources
    assert_status 1
    assert_eq "" "$OUT" "Ausgabe"
    assert_contains "$ERR" "'depends_on_sources' muss eine Blockliste"
    assert_contains "$ERR" "keine Inline-Liste"
}

test_manifest_list_rejects_empty_entry() {
    write_manifest 'depends_on_sources:' '  -' '  - fishbase'
    run_capture manifest_list "$TEST_TMP/plugin.yaml" depends_on_sources
    assert_status 1
    assert_contains "$ERR" "nicht leeren Einträgen"
}
