#!/usr/bin/env bash
# Tests für plugin_manifest_get und plugin_manifest_list aus core/plugin_api.sh

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

manifest_get() {
    ( source "$ETL_DIR/core/plugin_api.sh"; plugin_manifest_get "$@" )
}

test_manifest_get_reads_top_level_value_only() {
    write_manifest \
        'env:' \
        '  optional: true' \
        'optional: false   # Kommentar' \
        'other:' \
        '  placement_priority: 5'
    run_capture manifest_get "$TEST_TMP/plugin.yaml" optional
    assert_status 0
    assert_eq "false" "$OUT" "optional"
    run_capture manifest_get "$TEST_TMP/plugin.yaml" placement_priority
    assert_status 0
    assert_eq "" "$OUT" "verschachtelte placement_priority"
}

test_version_at_least_compares_parts_as_numbers() {
    source "$ETL_DIR/core/plugin_api.sh"
    version_at_least 3.47.0 3.47.0 || fail_case "3.47.0 >= 3.47.0"
    version_at_least 3.50.6 3.47.0 || fail_case "3.50.6 >= 3.47.0"
    version_at_least 4.0 3.47.0    || fail_case "4.0 >= 3.47.0"
    version_at_least 3.47.1 3.47   || fail_case "3.47.1 >= 3.47"
    if version_at_least 3.46.1 3.47.0; then fail_case "3.46.1 < 3.47.0"; fi
    if version_at_least 3.9.0 3.47.0;  then fail_case "3.9.0 < 3.47.0"; fi
}
