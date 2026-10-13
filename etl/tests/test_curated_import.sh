#!/usr/bin/env bash
# Tests für plugins/curated/import.sh gegen eine Mini-DB
#
# Das Plugin läuft als Kopie unter $TEST_TMP/etl, damit ein Fall seine CSV
# ändern kann, ohne das Repository anzufassen.

CURATED_CSV_HEADER="taxon_source,external_id,class,language,name,source_url"

# Kopiert core/ und das Plugin, legt die DB an und füllt sie wie nach der
# Identitäts-Stage: die fünf FishBase-Klassen der echten CSV und eine
# SeaLifeBase-Klasse mit endgültigen IDs und ihren Schlüsseln im ID-Register,
# dazu der einzige englische FishBase-Name, den die Fälle brauchen.
setup_curated() {
    mkdir -p "$TEST_TMP/etl/plugins"
    cp -R "$ETL_DIR/core" "$TEST_TMP/etl/core"
    cp -R "$ETL_DIR/plugins/curated" "$TEST_TMP/etl/plugins/curated"
    CURATED_IMPORT="$TEST_TMP/etl/plugins/curated/import.sh"
    CURATED_CSV="$TEST_TMP/etl/plugins/curated/data/class_common_names.csv"
    DB="$TEST_TMP/ref.db"

    "$TEST_TMP/etl/core/create_db.sh" --output "$DB" > /dev/null 2>&1
    sqlite3 "$DB" << 'SQL'
INSERT INTO classes (id, external_id, external_source, name, super_class) VALUES
    ('discere:class:1', '4', 'fishbase', 'Cladistii', 'Actinopterygii'),
    ('discere:class:2', '5', 'fishbase', 'Chondrostei', 'Actinopterygii'),
    ('discere:class:3', '7', 'fishbase', 'Teleostei', 'Actinopterygii'),
    ('discere:class:4', '8', 'fishbase', 'Coelacanthi', 'Sarcopterygii'),
    ('discere:class:5', '9', 'fishbase', 'Dipneusti', 'Sarcopterygii'),
    ('discere:class:6', '1', 'sealifebase', 'Turbellaria', 'Platyhelminthes');
INSERT INTO entity_source_keys (source, entity_type, external_id, entity_id, active) VALUES
    ('fishbase',    'class', '4', 'discere:class:1', 1),
    ('fishbase',    'class', '5', 'discere:class:2', 1),
    ('fishbase',    'class', '7', 'discere:class:3', 1),
    ('fishbase',    'class', '8', 'discere:class:4', 1),
    ('fishbase',    'class', '9', 'discere:class:5', 1),
    ('sealifebase', 'class', '1', 'discere:class:6', 1);
INSERT INTO common_names (entity_id, entity_type, language, name, source, is_preferred) VALUES
    ('discere:class:3', 'class', 'en', 'teleosts', 'fishbase', 1);
SQL
}

write_curated_csv() {
    { echo "$CURATED_CSV_HEADER"; printf '%s\n' "$@"; } > "$CURATED_CSV"
}

curated_count() {
    sqlite3 "$DB" "SELECT COUNT(*) FROM common_names WHERE source = 'curated' ${1:+AND $1};"
}

# Bricht der Import ab, darf er nichts geschrieben haben.
assert_import_rejected() {
    run_capture "$CURATED_IMPORT" --db "$DB"
    assert_status 1
    assert_contains "$ERR" "Ungültige Zeilen in class_common_names.csv:"
    assert_eq 0 "$(curated_count)" "curated-Zeilen nach dem Abbruch"
}

test_curated_imports_every_row() {
    setup_curated
    run_capture "$CURATED_IMPORT" --db "$DB" --download --version v25.04
    assert_status 0
    assert_eq "" "$OUT" "stdout"
    assert_contains "$ERR" "[WARN] [curated] Unbekanntes Argument: --version"
    assert_eq 15 "$(curated_count)" "curated-Zeilen"
    assert_eq 5 "$(curated_count "language = 'de'")" "de"
    assert_eq 5 "$(curated_count "language = 'fr'")" "fr"
    assert_eq 5 "$(curated_count "language = 'es'")" "es"
    assert_eq "discere:class:3|class|Echte Knochenfische|1" \
        "$(sqlite3 "$DB" "SELECT entity_id, entity_type, name, is_preferred FROM common_names
                         WHERE source = 'curated' AND language = 'de' AND entity_id = 'discere:class:3';")" \
        "Teleostei auf Deutsch"
    assert_eq "curated|CC BY-NC 4.0" "$(sqlite3 "$DB" "SELECT id, license_key FROM sources WHERE id = 'curated';")" \
        "sources-Eintrag"
}

test_curated_reimport_is_idempotent() {
    setup_curated
    run_capture "$CURATED_IMPORT" --db "$DB"
    assert_status 0
    local first
    first="$(sqlite3 "$DB" "SELECT COUNT(*) FROM common_names;")"
    run_capture "$CURATED_IMPORT" --db "$DB"
    assert_status 0
    assert_eq "$first" "$(sqlite3 "$DB" "SELECT COUNT(*) FROM common_names;")" "common_names nach Reimport"
    assert_eq 15 "$(curated_count)" "curated-Zeilen nach Reimport"
}

test_curated_accepts_language_the_taxon_source_has_no_name_in() {
    setup_curated
    write_curated_csv 'fishbase,9,Dipneusti,en,lungfishes,https://www.wikidata.org/wiki/Q168422'
    run_capture "$CURATED_IMPORT" --db "$DB"
    assert_status 0
    assert_eq 1 "$(curated_count "language = 'en'")" "englischer Name ohne FishBase-Namen"
}

test_curated_rejects_unknown_class() {
    setup_curated
    write_curated_csv \
        'fishbase,7,Teleosti,de,Echte Knochenfische,https://www.wikidata.org/wiki/Q204861' \
        'fishbase,6,Teleostei,fr,Téléostéens,https://www.wikidata.org/wiki/Q204861'
    assert_import_rejected
    assert_contains "$ERR" "Zeile 2: keine Klasse mit Schlüssel 'fishbase' / '7' im ID-Register und Namen 'Teleosti'"
    assert_contains "$ERR" "Zeile 3: keine Klasse mit Schlüssel 'fishbase' / '6' im ID-Register und Namen 'Teleostei'"
}

# Liefern zwei Quellen dieselbe Klasse, trägt die Zeile nach dem
# Zusammenführen die Spalten der gewichtigeren Quelle. Der FishBase-Schlüssel
# findet die Klasse trotzdem — über das Register.
test_curated_finds_class_through_register_after_merge() {
    setup_curated
    sqlite3 "$DB" "UPDATE classes SET external_source = 'othersource', external_id = '99'
                   WHERE id = 'discere:class:3';"
    write_curated_csv 'fishbase,7,Teleostei,de,Echte Knochenfische,https://www.wikidata.org/wiki/Q204861'
    run_capture "$CURATED_IMPORT" --db "$DB"
    assert_status 0
    assert_eq "discere:class:3" "$(sqlite3 "$DB" "SELECT entity_id FROM common_names WHERE source = 'curated';")" \
        "Klasse über das Register"
}

test_curated_rejects_taxon_source_outside_dependencies() {
    setup_curated
    write_curated_csv 'sealifebase,1,Turbellaria,de,Strudelwürmer,https://www.wikidata.org/wiki/Q166975'
    assert_import_rejected
    assert_contains "$ERR" "Zeile 2: Taxonquelle 'sealifebase' steht nicht in depends_on_sources"
}

test_curated_rejects_unknown_language() {
    setup_curated
    write_curated_csv 'fishbase,7,Teleostei,it,Teleostei,https://www.wikidata.org/wiki/Q204861'
    assert_import_rejected
    assert_contains "$ERR" "Zeile 2: Sprache 'it' ist nicht en, de, fr oder es"
}

test_curated_rejects_two_rows_for_same_class_and_language() {
    setup_curated
    write_curated_csv \
        'fishbase,7,Teleostei,de,Echte Knochenfische,https://www.wikidata.org/wiki/Q204861' \
        'fishbase,7,Teleostei,de,Teleosteer,https://www.wikidata.org/wiki/Q204861'
    assert_import_rejected
    assert_contains "$ERR" "Zeile 2: Zeile 3 nennt dieselbe Klasse in derselben Sprache"
    assert_contains "$ERR" "Zeile 3: Zeile 2 nennt dieselbe Klasse in derselben Sprache"
}

test_curated_rejects_name_the_taxon_source_already_has() {
    setup_curated
    write_curated_csv 'fishbase,7,Teleostei,en,bony fishes,https://www.wikidata.org/wiki/Q204861'
    assert_import_rejected
    assert_contains "$ERR" "Zeile 2: fishbase führt für diese Klasse schon einen Namen in 'en': teleosts"
}

test_curated_reports_every_empty_cell() {
    setup_curated
    write_curated_csv \
        'fishbase,,Teleostei,de,Echte Knochenfische,https://www.wikidata.org/wiki/Q204861' \
        'fishbase,7,,fr,Téléostéens,https://www.wikidata.org/wiki/Q204861' \
        'fishbase,7,Teleostei,,Teleósteos,https://www.wikidata.org/wiki/Q204861' \
        'fishbase,9,Dipneusti,de, ,https://www.wikidata.org/wiki/Q168422'
    assert_import_rejected
    assert_contains "$ERR" "Zeile 2: Spalte external_id ist leer"
    assert_contains "$ERR" "Zeile 3: Spalte class ist leer"
    assert_contains "$ERR" "Zeile 4: Spalte language ist leer"
    assert_contains "$ERR" "Zeile 5: Spalte name ist leer"
}

# Eine zu kurze Zeile füllt .import mit NULL statt ''.
test_curated_reports_missing_trailing_cells() {
    setup_curated
    write_curated_csv 'fishbase,7,Teleostei,de'
    assert_import_rejected
    assert_contains "$ERR" "Zeile 2: Spalte name ist leer"
    assert_contains "$ERR" "Zeile 2: Spalte source_url ist leer"
}

test_curated_rejects_unexpected_header() {
    setup_curated
    printf '%s\n' "taxon_source,external_id,class,name,language,source_url" \
        'fishbase,7,Teleostei,Echte Knochenfische,de,https://www.wikidata.org/wiki/Q204861' > "$CURATED_CSV"
    run_capture "$CURATED_IMPORT" --db "$DB"
    assert_status 1
    assert_contains "$ERR" "Kopfzeile von class_common_names.csv ist 'taxon_source,external_id,class,name,language,source_url'"
}

test_curated_keeps_previous_rows_when_rejecting() {
    setup_curated
    run_capture "$CURATED_IMPORT" --db "$DB"
    assert_status 0
    write_curated_csv 'fishbase,7,Teleostei,xx,Teleostei,https://www.wikidata.org/wiki/Q204861'
    run_capture "$CURATED_IMPORT" --db "$DB"
    assert_status 1
    assert_eq 15 "$(curated_count)" "curated-Zeilen nach dem Abbruch"
}
