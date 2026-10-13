#!/usr/bin/env bash
# Tests für core/plugin_order.sh und die Manifest-Prüfung in
# core/validate_plugin.sh

plugin_order() {
    "$ETL_DIR/core/plugin_order.sh" --plugins-dir "$TEST_TMP/plugins" "$@"
}

test_order_follows_dependency_chain() {
    make_plugin "$TEST_TMP/plugins" zeta
    make_plugin "$TEST_TMP/plugins" alpha 'depends_on_sources:' '  - zeta'
    make_plugin "$TEST_TMP/plugins" mid 'depends_on_sources:' '  - alpha'
    run_capture plugin_order
    assert_status 0
    assert_eq "zeta alpha mid" "$(echo $OUT)" "Reihenfolge"
}

test_order_breaks_ties_alphabetically() {
    make_plugin "$TEST_TMP/plugins" base
    make_plugin "$TEST_TMP/plugins" beta 'depends_on_sources:' '  - base'
    make_plugin "$TEST_TMP/plugins" alpha 'depends_on_sources:' '  - base'
    make_plugin "$TEST_TMP/plugins" zulu
    run_capture plugin_order
    assert_status 0
    assert_eq "base alpha beta zulu" "$(echo $OUT)" "Reihenfolge"
}

test_order_skips_template_directories() {
    make_plugin "$TEST_TMP/plugins" alpha
    make_plugin "$TEST_TMP/plugins" _template
    run_capture plugin_order
    assert_status 0
    assert_eq "alpha" "$OUT" "Reihenfolge"
}

test_selection_pulls_in_dependencies_transitively() {
    make_plugin "$TEST_TMP/plugins" a 'depends_on_sources:' '  - b'
    make_plugin "$TEST_TMP/plugins" b 'depends_on_sources:' '  - c'
    make_plugin "$TEST_TMP/plugins" c
    make_plugin "$TEST_TMP/plugins" d
    run_capture plugin_order a
    assert_status 0
    assert_eq "c b a" "$(echo $OUT)" "Reihenfolge"
    assert_contains "$ERR" "Abhängigkeit hinzugenommen: 'b' (für 'a')."
    assert_contains "$ERR" "Abhängigkeit hinzugenommen: 'c' (für 'b')."
}

test_unknown_plugin_aborts() {
    make_plugin "$TEST_TMP/plugins" a
    run_capture plugin_order nope
    assert_status 1
    assert_contains "$ERR" "Unbekanntes Plugin 'nope'"
}

test_unknown_dependency_aborts() {
    make_plugin "$TEST_TMP/plugins" a 'depends_on_sources:' '  - missing'
    run_capture plugin_order
    assert_status 1
    assert_eq "" "$OUT" "Ausgabe"
    assert_contains "$ERR" "Unbekannte Abhängigkeit: 'a' hängt von 'missing' ab"
}

test_cycle_aborts_naming_its_members() {
    make_plugin "$TEST_TMP/plugins" a 'depends_on_sources:' '  - b'
    make_plugin "$TEST_TMP/plugins" b 'depends_on_sources:' '  - a'
    make_plugin "$TEST_TMP/plugins" c 'depends_on_sources:' '  - a'
    make_plugin "$TEST_TMP/plugins" d
    run_capture plugin_order
    assert_status 1
    assert_eq "" "$OUT" "Ausgabe"
    assert_eq "[ERROR] [plugin_order] Zyklus in depends_on_sources zwischen: a b" \
        "$(echo "$ERR" | tail -n 1)" "Meldung"
}

test_self_dependency_is_a_cycle() {
    make_plugin "$TEST_TMP/plugins" a 'depends_on_sources:' '  - a'
    run_capture plugin_order
    assert_status 1
    assert_contains "$ERR" "Zyklus in depends_on_sources zwischen: a"
}

test_duplicate_placement_priority_aborts() {
    make_plugin "$TEST_TMP/plugins" a 'placement_priority: 10'
    make_plugin "$TEST_TMP/plugins" b 'placement_priority: 10'
    make_plugin "$TEST_TMP/plugins" c 'placement_priority: 20'
    make_plugin "$TEST_TMP/plugins" d
    run_capture plugin_order
    assert_status 1
    assert_contains "$ERR" "Doppelte placement_priority — placement_priority 10: a, b"
    assert_not_contains "$ERR" "placement_priority 20"
}

test_no_enrich_skips_optional_source_and_its_dependents() {
    make_plugin "$TEST_TMP/plugins" opt 'optional: true'
    make_plugin "$TEST_TMP/plugins" uses_opt 'depends_on_sources:' '  - opt'
    make_plugin "$TEST_TMP/plugins" uses_uses_opt 'depends_on_sources:' '  - uses_opt'
    make_plugin "$TEST_TMP/plugins" plain 'optional: false'

    run_capture plugin_order
    assert_status 0
    assert_eq "opt plain uses_opt uses_uses_opt" "$(echo $OUT)" "Reihenfolge ohne --no-enrich"

    run_capture plugin_order --no-enrich
    assert_status 0
    assert_eq "plain" "$OUT" "Reihenfolge mit --no-enrich"
    assert_contains "$ERR" "Übersprungen (--no-enrich): 'opt' ist optional."
    assert_contains "$ERR" "Übersprungen (--no-enrich): 'uses_opt' hängt vom übersprungenen 'opt' ab."
    assert_contains "$ERR" "Übersprungen (--no-enrich): 'uses_uses_opt' hängt vom übersprungenen 'uses_opt' ab."
}

test_validation_rejects_malformed_manifest_fields() {
    make_plugin "$TEST_TMP/plugins" a \
        'optional: yes' \
        'placement_priority: high' \
        'depends_on_sources:' \
        '  - Fish Base'
    sed -i.bak 's/^source: a$/source: other/' "$TEST_TMP/plugins/a/plugin.yaml"
    run_capture "$ETL_DIR/core/validate_plugin.sh" "$TEST_TMP/plugins/a"
    assert_status 1
    assert_contains "$ERR" "'source' (other) muss dem Verzeichnisnamen (a) entsprechen"
    assert_contains "$ERR" "'depends_on_sources' enthält 'Fish Base' — kein Quellenschlüssel"
    assert_contains "$ERR" "'optional' muss true oder false sein"
    assert_contains "$ERR" "'placement_priority' muss eine ganze Zahl sein"
}

test_validation_does_not_require_export_sql() {
    make_plugin "$TEST_TMP/plugins" a
    run_capture "$ETL_DIR/core/validate_plugin.sh" "$TEST_TMP/plugins/a"
    assert_status 0
}

test_real_plugins_are_ordered_with_curated_after_fishbase() {
    run_capture "$ETL_DIR/core/plugin_order.sh" --plugins-dir "$ETL_DIR/plugins"
    assert_status 0
    assert_eq "fishbase curated sealifebase" "$(echo $OUT)" "Reihenfolge"
}
