#!/usr/bin/env bash
# Tests für plugin_report (core/plugin_api.sh) und core/report_summary.sh

# Läuft wie in einem Plugin mit PLUGIN_SOURCE; die Einträge kommen von stdin.
report_as() {
    local source="$1"
    ( source "$ETL_DIR/core/plugin_api.sh"; PLUGIN_SOURCE="$source"; plugin_report )
}

test_report_appends_entries_with_source_and_one_header() {
    export DISCERE_REPORT_DIR="$TEST_TMP/report"
    printf 'none\t42\tAbc def\t\n\n' | report_as inat
    printf 'ambiguous\t43\tGhi jkl\tdiscere:a, discere:b\n' | report_as inat
    assert_eq "source	category	key	name	detail
inat	none	42	Abc def	
inat	ambiguous	43	Ghi jkl	discere:a, discere:b" "$(cat "$TEST_TMP/report/inat.tsv")" "Bericht"
}

test_report_without_directory_only_counts() {
    unset DISCERE_REPORT_DIR
    run_capture report_as inat <<< $'none\t42\tAbc def\t\nnone\t43\tGhi\t'
    assert_status 0
    assert_contains "$ERR" "Kein Build-Bericht (DISCERE_REPORT_DIR nicht gesetzt): 2 Einträge nicht festgehalten."
    assert_eq "" "$(find "$TEST_TMP" -name '*.tsv')" "Berichtsdateien"
}

test_report_summary_counts_per_source_and_category() {
    export DISCERE_REPORT_DIR="$TEST_TMP/report"
    printf 'none\t1\ta\t\nambiguous\t2\tb\t\nnone\t3\tc\t\n' | report_as zeta
    printf 'ambiguous\t4\td\t\n' | report_as alpha
    run_capture "$ETL_DIR/core/report_summary.sh" "$TEST_TMP/report"
    assert_status 0
    assert_eq "alpha: ambiguous 1
zeta: ambiguous 1 none 2" "$OUT" "Zusammenfassung"
}

test_report_summary_without_entries() {
    mkdir -p "$TEST_TMP/report"
    run_capture "$ETL_DIR/core/report_summary.sh" "$TEST_TMP/report"
    assert_status 0
    assert_eq "keine Einträge" "$OUT" "Zusammenfassung"
}
