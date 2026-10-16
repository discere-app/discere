#!/usr/bin/env bash
# Tests für die Validierung am Ende des Builds (core/validate.sh mit
# core/sql/validate.sql): Mindestzahlen gelten nur, wenn ihre Voraussetzung
# im Build gelaufen ist, Invarianten immer, und eine Zeile ohne gültige
# Voraussetzung bricht ab.

# Setzt RAN auf die --ran-Argumente, die build.sh übergibt: jedes Plugin, das
# core/plugin_order.sh mit den übergebenen Flags ausführt, und enrich ohne
# --no-enrich.
ran_as_build() {
    local plugin
    RAN=()
    for plugin in $("$ETL_DIR/core/plugin_order.sh" --plugins-dir "$ETL_DIR/plugins" "$@" 2> /dev/null); do
        RAN+=(--ran "$plugin")
    done
    [[ " $* " == *" --no-enrich "* ]] || RAN+=(--ran enrich)
}

# Legt unter $TEST_TMP/valid.db eine DB an, die jede Mindestzahl aus
# validate.sql außer locale_place_mappings knapp erfüllt und jede Invariante
# einhält; locale_place_mappings bleibt leer.
create_validatable_db() {
    DB="$TEST_TMP/valid.db"
    "$ETL_DIR/core/create_db.sh" --output "$DB" > /dev/null 2>&1
    sqlite3 "$DB" << 'SQL'
CREATE TEMP TABLE n AS
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 400000)
SELECT i FROM n;

INSERT INTO classes (id, external_id, external_source, name, super_class)
SELECT 'discere:class:' || i, i, 'fishbase', 'C' || i, 'S' FROM n WHERE i <= 10;
INSERT INTO orders (id, external_id, external_source, name)
SELECT 'discere:order:' || i, i, 'fishbase', 'O' || i FROM n WHERE i <= 50;
INSERT INTO families (id, external_id, external_source, name)
SELECT 'discere:family:' || i, i, 'fishbase', 'F' || i FROM n WHERE i <= 400;
INSERT INTO genera (id, external_id, external_source, name)
SELECT 'discere:genus:' || i, i, 'fishbase', 'G' || i FROM n WHERE i <= 5000;
INSERT INTO species (id, external_id, external_source, name, status)
SELECT 'discere:species:' || i, i, 'fishbase', 's' || i, 'active' FROM n WHERE i <= 30000;
INSERT INTO entity_source_keys (source, entity_type, external_id, entity_id, active)
SELECT 'fishbase', 'species', i, 'discere:species:' || i, 1 FROM n WHERE i <= 30000;
INSERT INTO pictures (id, species, origin, is_usable)
SELECT 'discere:fishbase_pic:' || i, 'discere:species:' || i, 'fishbase', i <= 1000
FROM n WHERE i <= 10000;
INSERT INTO common_names (entity_id, entity_type, language, name, source)
SELECT 'discere:species:' || (i % 30000 + 1), 'species',
       CASE WHEN i <= 30000 THEN 'en' WHEN i <= 40000 THEN 'de' ELSE 'fr' END,
       'N' || i, 'fishbase'
FROM n WHERE i <= 100000;
INSERT INTO taxonomy_traits (entity_id, entity_type, trait_key, trait_value_num, source)
SELECT 'discere:species:' || (i % 30000 + 1), 'species', 'k' || i, 1, 'fishbase'
FROM n WHERE i <= 10000;
INSERT INTO taxonomy_distribution_regions
    (entity_id, entity_type, source, region_scope, region_key, region_label)
SELECT 'discere:species:' || (i % 30000 + 1), 'species', 'fishbase', 'country', 'r' || i, 'R'
FROM n;
SQL
}

# Füllt locale_place_mappings mit <anzahl> Zeilen.
seed_locale_place_mappings() {
    sqlite3 "$DB" "
        WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < $1)
        INSERT INTO locale_place_mappings
            (locale, language_code, country_code_alpha2, country_code_numeric, inat_place_id)
        SELECT 'l' || i, 'de', 'DE', '276', i FROM n;"
}

validate() {
    run_capture "$ETL_DIR/core/validate.sh" --db "$DB" --plugins-dir "$ETL_DIR/plugins" "$@"
}

# Kopiert core/ nach $TEST_TMP/etl, damit ein Fall validate.sql ändern kann.
validate_with_copied_core() {
    run_capture "$TEST_TMP/etl/core/validate.sh" --db "$DB" --plugins-dir "$ETL_DIR/plugins" "$@"
}

copy_core() {
    mkdir -p "$TEST_TMP/etl"
    cp -R "$ETL_DIR/core" "$TEST_TMP/etl/core"
}

test_validate_complete_build_passes_with_all_minimums_met() {
    create_validatable_db
    seed_locale_place_mappings 70
    ran_as_build
    validate "${RAN[@]}"
    assert_status 0
    assert_contains "$ERR" "Validierung OK."
    assert_not_contains "$ERR" "übersprungen"
}

# Ohne Stage 01b fehlen die Ortszuordnungen; die übrigen Mindestzahlen und
# alle Invarianten gelten weiter.
test_validate_no_enrich_build_passes_without_locale_place_mappings() {
    create_validatable_db
    ran_as_build --no-enrich
    validate "${RAN[@]}"
    assert_status 0
    assert_contains "$ERR" "übersprungen: Stage 01b nicht gelaufen"
    printf '%s\n' "$ERR" | grep -Eq 'taxonomy_distribution_regions +400000$' \
        || fail_case "Mindestzahl ohne Stage-01b-Voraussetzung nicht geprüft:"$'\n'"$ERR"
}

test_validate_complete_build_fails_on_too_few_locale_place_mappings() {
    create_validatable_db
    seed_locale_place_mappings 69
    ran_as_build
    validate "${RAN[@]}"
    assert_status 1
    assert_contains "$ERR" "FEHLER: locale_place_mappings — 69 (erwartet >= 70)"
    assert_contains "$ERR" "Validierung fehlgeschlagen."
}

# Ein Teilbuild nur mit fishbase prüft keine Mindestzahl, die SeaLifeBase
# voraussetzt, und nennt den Grund.
test_validate_partial_build_skips_minimums_of_plugins_it_did_not_run() {
    create_validatable_db
    sqlite3 "$DB" "DELETE FROM taxonomy_distribution_regions;"
    validate --ran fishbase --ran curated
    assert_status 0
    assert_contains "$ERR" "übersprungen: Plugin sealifebase nicht gelaufen"
}

test_validate_checks_invariants_in_partial_build() {
    create_validatable_db
    sqlite3 "$DB" "UPDATE species SET id = 'discere:fishbase_species:1' WHERE id = 'discere:species:1';"
    validate --ran fishbase
    assert_status 1
    assert_contains "$ERR" "FEHLER: id:species — 29999 (erwartet >= 30000)"
}

test_validate_aborts_on_unknown_requirement() {
    create_validatable_db
    copy_core
    sed -i '' "s/'enrich'/'enrichment'/" "$TEST_TMP/etl/core/sql/validate.sql"
    validate_with_copied_core --ran fishbase
    assert_status 1
    assert_contains "$ERR" "locale_place_mappings: unbekannte Voraussetzung 'enrichment' — Validierung abgebrochen."
}

test_validate_aborts_on_row_without_requirement() {
    create_validatable_db
    copy_core
    printf '%s\n' "SELECT 'extra', 1, 1;" >> "$TEST_TMP/etl/core/sql/validate.sql"
    ran_as_build
    validate_with_copied_core "${RAN[@]}"
    assert_status 1
    assert_contains "$ERR" "Zeile ohne die Spalten tbl | n | min | requires: extra|1|1"
}

test_validate_aborts_on_empty_requirement() {
    create_validatable_db
    copy_core
    printf '%s\n' "SELECT 'extra', 1, 1, '';" >> "$TEST_TMP/etl/core/sql/validate.sql"
    ran_as_build
    validate_with_copied_core "${RAN[@]}"
    assert_status 1
    assert_contains "$ERR" "extra: keine Voraussetzung (requires) — Validierung abgebrochen."
}

test_validate_aborts_on_sql_error() {
    create_validatable_db
    copy_core
    printf '%s\n' "SELECT broken FROM;" >> "$TEST_TMP/etl/core/sql/validate.sql"
    ran_as_build
    validate_with_copied_core "${RAN[@]}"
    assert_status 1
    assert_contains "$ERR" "core/sql/validate.sql fehlgeschlagen — Validierung abgebrochen."
}

# Ein ungültiges Plugin bricht die Validierung ab, und der Grund aus
# core/plugin_order.sh bleibt im Log.
test_validate_aborts_on_invalid_plugin_with_reason() {
    create_validatable_db
    make_plugin "$TEST_TMP/plugins" broken
    printf 'name: broken\nversion: 1\n' > "$TEST_TMP/plugins/broken/plugin.yaml"
    run_capture "$ETL_DIR/core/validate.sh" --db "$DB" --plugins-dir "$TEST_TMP/plugins" --ran broken
    assert_status 1
    assert_contains "$ERR" "Plugins unter $TEST_TMP/plugins nicht lesbar."
    assert_contains "$ERR" "Pflichtfeld 'source' fehlt"
    assert_not_contains "$ERR" "Validierung OK."
}
