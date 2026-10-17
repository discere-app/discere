#!/usr/bin/env bash
# Tests für die Validierung am Ende des Builds (core/validate.sh mit
# core/sql/validate.sql): Mindestzahlen gelten nur, wenn ihre Voraussetzung
# im Build gelaufen ist, Invarianten immer, und eine Zeile ohne gültige
# Voraussetzung bricht ab. Dazu, was build.sh als gelaufen übergibt.

# --ran-Argumente eines vollständigen Builds mit den Plugins unter plugins/
# und eines Builds mit --no-enrich (ohne inaturalist und Stage 01b). Dass
# build.sh genau das übergibt, prüfen die Fälle test_build_passes_….
COMPLETE_RAN=(--ran curated --ran fishbase --ran inaturalist --ran sealifebase --ran enrich)
NO_ENRICH_RAN=(--ran curated --ran fishbase --ran sealifebase)

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
UPDATE families SET is_placeholder = 1 WHERE CAST(external_id AS INTEGER) <= 150;
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
    validate "${COMPLETE_RAN[@]}"
    assert_status 0
    assert_contains "$ERR" "Validierung OK."
    assert_not_contains "$ERR" "übersprungen"
}

# Ohne Stage 01b fehlen die Ortszuordnungen; die übrigen Mindestzahlen und
# alle Invarianten gelten weiter.
test_validate_no_enrich_build_passes_without_locale_place_mappings() {
    create_validatable_db
    validate "${NO_ENRICH_RAN[@]}"
    assert_status 0
    assert_contains "$ERR" "übersprungen: Stage 01b nicht gelaufen"
    printf '%s\n' "$ERR" | grep -Eq 'taxonomy_distribution_regions +400000$' \
        || fail_case "Mindestzahl ohne Stage-01b-Voraussetzung nicht geprüft:"$'\n'"$ERR"
}

test_validate_complete_build_fails_when_the_placeholder_rule_stops_matching() {
    create_validatable_db
    seed_locale_place_mappings 70
    sqlite3 "$DB" "UPDATE families SET is_placeholder = 0 WHERE id = 'discere:family:1';"
    validate "${COMPLETE_RAN[@]}"
    assert_status 1
    assert_contains "$ERR" "FEHLER: rank placeholders — 149 (erwartet >= 150)"
}

test_validate_complete_build_fails_on_too_few_locale_place_mappings() {
    create_validatable_db
    seed_locale_place_mappings 69
    validate "${COMPLETE_RAN[@]}"
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

# Jede aktive Art mit Gattung braucht einen bevorzugten wissenschaftlichen
# Namen; Arten ohne Gattung und veraltete Arten sind ausgenommen.
test_validate_fails_on_active_species_with_genus_without_preferred_name() {
    create_validatable_db
    seed_locale_place_mappings 70
    sqlite3 "$DB" "
        UPDATE species SET genus = 'discere:genus:1' WHERE id IN ('discere:species:1', 'discere:species:2');
        INSERT INTO species (id, external_id, external_source, name, genus, status)
        VALUES ('discere:species:30001', '30001', 'fishbase', 'vetus', 'discere:genus:1', 'deprecated');
        INSERT INTO entity_source_keys (source, entity_type, external_id, entity_id, active)
        VALUES ('fishbase', 'species', '30001', 'discere:species:30001', 0);
        INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
            ('discere:species:1', 'G1 s1', 'g1 s1', 'valid', 'fishbase', 1),
            ('discere:species:2', 'G1 s2', 'g1 s2', 'valid', 'fishbase', 1);"
    "$ETL_DIR/core/lookup.sh" --db "$DB" > /dev/null 2>&1
    validate "${COMPLETE_RAN[@]}"
    assert_status 0
    sqlite3 "$DB" "UPDATE species_scientific_names SET is_preferred = 0, name_status = 'synonym'
                   WHERE species_id = 'discere:species:2';"
    "$ETL_DIR/core/lookup.sh" --db "$DB" > /dev/null 2>&1
    validate "${COMPLETE_RAN[@]}"
    assert_status 1
    assert_contains "$ERR" "FEHLER: species (preferred name) — 1 (erwartet >= 2)"
}

# Der bevorzugte Name einer Art ohne Gattung endet auf ihr Epitheton; eine
# Art ohne Gattung und ohne bevorzugten Namen prüft diese Zeile nicht.
test_validate_fails_on_preferred_name_of_species_without_genus_with_other_epithet() {
    create_validatable_db
    seed_locale_place_mappings 70
    sqlite3 "$DB" "
        INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
            ('discere:species:1', 'Abra s1', 'abra s1', 'valid', 'sealifebase', 1),
            ('discere:species:2', 'Abra s2', 'abra s2', 'valid', 'sealifebase', 1);"
    "$ETL_DIR/core/lookup.sh" --db "$DB" > /dev/null 2>&1
    validate "${COMPLETE_RAN[@]}"
    assert_status 0
    sqlite3 "$DB" "UPDATE species_scientific_names SET name = 'Abra s22', normalized_name = 'abra s22'
                   WHERE species_id = 'discere:species:2';"
    "$ETL_DIR/core/lookup.sh" --db "$DB" > /dev/null 2>&1
    validate "${COMPLETE_RAN[@]}"
    assert_status 1
    assert_contains "$ERR" "FEHLER: species without genus (preferred name) — 1 (erwartet >= 2)"
}

# Der bevorzugte Name einer Art ist ihr eigener: Eine Art Cytherea albus mit
# dem bevorzugten Namen Callista niger, Synonym von Callista chione, zöge
# diesen Namen im Lookup auf sich.
test_validate_fails_on_preferred_name_other_than_own_binomial() {
    create_validatable_db
    seed_locale_place_mappings 70
    sqlite3 "$DB" "
        INSERT INTO genera (id, external_id, external_source, name) VALUES
            ('discere:genus:5001', '5001', 'fishbase', 'Cytherea'),
            ('discere:genus:5002', '5002', 'fishbase', ' Callista');
        UPDATE species SET genus = 'discere:genus:5001', name = 'albus' WHERE id = 'discere:species:1';
        UPDATE species SET genus = 'discere:genus:5002', name = 'chione ' WHERE id = 'discere:species:2';
        INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
            ('discere:species:1', 'Callista niger', 'callista niger', 'valid', 'fishbase', 1),
            ('discere:species:2', 'Callista chione', 'callista chione', 'valid', 'fishbase', 1),
            ('discere:species:2', 'Callista niger', 'callista niger', 'synonym', 'fishbase', 0);"
    "$ETL_DIR/core/lookup.sh" --db "$DB" > /dev/null 2>&1
    assert_eq "discere:species:1" \
        "$(sqlite3 "$DB" "SELECT species_id FROM species_name_lookup WHERE normalized_name = 'callista niger';")" \
        "Lookup callista niger"
    validate "${COMPLETE_RAN[@]}"
    assert_status 1
    assert_contains "$ERR" "FEHLER: species (preferred name) — 1 (erwartet >= 2)"
}

# Eine Quelle führt je Art höchstens einen bevorzugten Namen.
test_validate_fails_on_two_preferred_names_of_one_species_in_one_source() {
    create_validatable_db
    seed_locale_place_mappings 70
    sqlite3 "$DB" "
        INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
            ('discere:species:1', 'G1 s1', 'g1 s1', 'valid', 'fishbase', 1),
            ('discere:species:1', 'G1 t1', 'g1 t1', 'valid', 'fishbase', 1),
            ('discere:species:2', 'G2 s2', 'g2 s2', 'valid', 'fishbase', 1),
            ('discere:species:2', 'G2 s2', 'g2 s2', 'valid', 'sealifebase', 1);"
    "$ETL_DIR/core/lookup.sh" --db "$DB" > /dev/null 2>&1
    validate "${COMPLETE_RAN[@]}"
    assert_status 1
    assert_contains "$ERR" "FEHLER: preferred names (per source) — 3 (erwartet >= 4)"
}

# Eine iNaturalist-Zuordnung braucht die eigene Kette bis zur Klasse: bei
# einer Art ihre, bei einem Namensschlüssel die jeder gleichnamigen Entität.
test_validate_fails_on_inaturalist_mapping_without_chain() {
    create_validatable_db
    seed_locale_place_mappings 70
    sqlite3 "$DB" "
        UPDATE orders SET class = 'discere:class:1' WHERE id = 'discere:order:1';
        UPDATE families SET \"order\" = 'discere:order:1' WHERE id = 'discere:family:1';
        UPDATE genera SET family = 'discere:family:1' WHERE id = 'discere:genus:1';
        UPDATE species SET genus = 'discere:genus:1' WHERE id = 'discere:species:1';
        INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred)
        VALUES ('discere:species:1', 'G1 s1', 'g1 s1', 'valid', 'fishbase', 1);
        INSERT INTO entity_external_ids (entity_id, entity_type, provider, external_id) VALUES
            ('discere:species:1', 'species', 'inaturalist', '1'),
            ('genus:g1',          'genera',  'inaturalist', '2');"
    "$ETL_DIR/core/lookup.sh" --db "$DB" > /dev/null 2>&1
    validate "${COMPLETE_RAN[@]}"
    assert_status 0
    sqlite3 "$DB" "
        INSERT INTO genera (id, external_id, external_source, name)
        VALUES ('discere:genus:5001', '5001', 'sealifebase', 'G1');
        INSERT INTO entity_external_ids (entity_id, entity_type, provider, external_id)
        VALUES ('discere:species:2', 'species', 'inaturalist', '3');"
    validate "${COMPLETE_RAN[@]}"
    assert_status 1
    assert_contains "$ERR" "FEHLER: inaturalist (species with chain) — 1 (erwartet >= 2)"
    assert_contains "$ERR" "FEHLER: inaturalist (name keys with chain) — 0 (erwartet >= 1)"
}

# Eine Klasse ohne Stamm ist keine Kette, auch für ihren eigenen Schlüssel.
test_validate_fails_on_inaturalist_class_key_without_phylum() {
    create_validatable_db
    seed_locale_place_mappings 70
    sqlite3 "$DB" "
        INSERT INTO entity_external_ids (entity_id, entity_type, provider, external_id)
        VALUES ('class:c1', 'classes', 'inaturalist', '1');"
    validate "${COMPLETE_RAN[@]}"
    assert_status 0
    sqlite3 "$DB" "UPDATE classes SET super_class = ' ' WHERE id = 'discere:class:1';"
    validate "${COMPLETE_RAN[@]}"
    assert_status 1
    assert_contains "$ERR" "FEHLER: inaturalist (name keys with chain) — 0 (erwartet >= 1)"
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
    validate_with_copied_core "${COMPLETE_RAN[@]}"
    assert_status 1
    assert_contains "$ERR" "Zeile ohne die Spalten tbl | n | min | requires: extra|1|1"
}

test_validate_aborts_on_empty_requirement() {
    create_validatable_db
    copy_core
    printf '%s\n' "SELECT 'extra', 1, 1, '';" >> "$TEST_TMP/etl/core/sql/validate.sql"
    validate_with_copied_core "${COMPLETE_RAN[@]}"
    assert_status 1
    assert_contains "$ERR" "extra: keine Voraussetzung (requires) — Validierung abgebrochen."
}

test_validate_aborts_on_sql_error() {
    create_validatable_db
    copy_core
    printf '%s\n' "SELECT broken FROM;" >> "$TEST_TMP/etl/core/sql/validate.sql"
    validate_with_copied_core "${COMPLETE_RAN[@]}"
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

# Kopiert build.sh und core/ nach $TEST_TMP/etl, ohne Netz: Stage 01b ist ein
# Stub, core/validate.sh schreibt nur seine Argumente nach
# $TEST_TMP/validate.args. Plugins:
#   fishy  liefert Entitäten (placement_priority 10): eine Art samt Kette
#   extra  ergänzt, hängt von fishy ab
#   lone   ergänzt, ohne Abhängigkeit
#   opt    optional (--no-enrich überspringt es)
# Gebaut wird mit --initial, ohne Vorgänger: Für die übergebenen Werte zählt
# nur, welche Plugins und Stages gelaufen sind.
create_validating_etl() {
    mkdir -p "$TEST_TMP/etl"
    cp "$ETL_DIR/build.sh" "$TEST_TMP/etl/"
    cp -R "$ETL_DIR/core" "$TEST_TMP/etl/core"
    printf '#!/usr/bin/env bash\n' > "$TEST_TMP/etl/core/seed_locale_place_mappings.sh"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s"\n' "$TEST_TMP/validate.args" \
        > "$TEST_TMP/etl/core/validate.sh"
    local plugins="$TEST_TMP/etl/plugins"
    make_plugin "$plugins" fishy 'placement_priority: 10'
    make_plugin "$plugins" extra 'depends_on_sources:' '  - fishy'
    make_plugin "$plugins" lone
    make_plugin "$plugins" opt 'optional: true'
    cat > "$plugins/fishy/import.sh" << 'IMPORT'
#!/usr/bin/env bash
[[ "$1" == --db ]] || exit 1
sqlite3 "$2" << 'SQL'
INSERT INTO classes (id, external_id, external_source, name, super_class) VALUES
    ('discere:fishy_class:1', '1', 'fishy', 'Teleostei', 'Actinopterygii');
INSERT INTO orders (id, external_id, external_source, name, class) VALUES
    ('discere:fishy_order:1', '1', 'fishy', 'Ovalentaria', 'discere:fishy_class:1');
INSERT INTO families (id, external_id, external_source, name, "order") VALUES
    ('discere:fishy_family:1', '1', 'fishy', 'Pomacentridae', 'discere:fishy_order:1');
INSERT INTO genera (id, external_id, external_source, name, family) VALUES
    ('discere:fishy_genus:1', '1', 'fishy', 'Amphiprion', 'discere:fishy_family:1');
INSERT INTO species (id, external_id, external_source, name, genus, status) VALUES
    ('discere:fishy_species:1', '1', 'fishy', 'ocellaris', 'discere:fishy_genus:1', 'active');
INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
    ('discere:fishy_species:1', 'Amphiprion ocellaris', 'amphiprion ocellaris', 'valid', 'fishy', 1);
SQL
IMPORT
}

# Baut mit den übergebenen Flags bis zum Ende und setzt RAN_PASSED auf die
# --ran-Werte, die build.sh an core/validate.sh übergeben hat, sortiert und
# durch Leerzeichen getrennt.
build_and_capture_ran() {
    run_capture "$TEST_TMP/etl/build.sh" --output "$TEST_TMP/out.db" --no-download --initial "$@"
    assert_status 0
    assert_contains "$ERR" "=== Build abgeschlossen"
    RAN_PASSED="$(sed -n '/^--ran$/{n;p;}' "$TEST_TMP/validate.args" | sort | tr '\n' ' ')"
}

test_build_passes_every_plugin_and_enrich_to_validation() {
    create_validating_etl
    build_and_capture_ran
    assert_eq "enrich extra fishy lone opt " "$RAN_PASSED" "--ran"
}

test_build_passes_neither_enrich_nor_optional_plugins_with_no_enrich() {
    create_validating_etl
    build_and_capture_ran --no-enrich
    assert_eq "extra fishy lone " "$RAN_PASSED" "--ran"
}

test_build_passes_only_selected_plugins_and_dependencies_to_validation() {
    create_validating_etl
    build_and_capture_ran --plugin extra
    assert_eq "enrich extra fishy " "$RAN_PASSED" "--ran"
}
