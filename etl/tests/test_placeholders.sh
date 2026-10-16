#!/usr/bin/env bash
# Tests für die Rang-Platzhalter (core/placeholders.sh, core/sql/placeholders.sql)

# Legt unter $TEST_TMP/ref.db eine Taxonomie an, deren Namen alle
# Schreibweisen der Platzhalter abdecken, die die Quellen führen, dazu echte
# Namen, die einem Platzhalter ähneln. Unter jedem Taxon hängt eine Kette bis
# zu einer Art; die Kette unter der Familie „Not assigned“ trägt zwei aktive
# und eine veraltete Art.
create_placeholder_db() {
    DB="$TEST_TMP/ref.db"
    "$ETL_DIR/core/create_db.sh" --output "$DB" > /dev/null 2>&1
    sqlite3 "$DB" << 'SQL'
INSERT INTO classes (id, external_id, external_source, name, super_class) VALUES
    ('discere:class:1', '1', 'sealifebase', 'Not assigned', ''),
    ('discere:class:2', '2', 'sealifebase', 'Incertae sedis (Nemertea)', ''),
    ('discere:class:3', '3', 'sealifebase', 'Incerate sedis (Dinoflagellata)', ''),
    ('discere:class:4', '4', 'sealifebase', 'Gastropoda', '');
INSERT INTO orders (id, external_id, external_source, name, class) VALUES
    ('discere:order:1', '1', 'sealifebase', 'Not assigned', 'discere:class:4'),
    ('discere:order:2', '2', 'sealifebase', ' not ASSIGNED ', 'discere:class:4'),
    ('discere:order:3', '3', 'sealifebase', 'Nudibranchia', 'discere:class:4'),
    ('discere:order:4', '4', 'fishbase', 'Eupercaria/misc', 'discere:class:4');
INSERT INTO families (id, external_id, external_source, name, "order") VALUES
    ('discere:family:1', '1', 'sealifebase', 'Not assigned', 'discere:order:3'),
    ('discere:family:2', '2', 'sealifebase', 'Incertae sedis', 'discere:order:3'),
    ('discere:family:3', '3', 'sealifebase', 'Tetraphyllidea Incertae sedis', 'discere:order:3'),
    ('discere:family:4', '4', 'sealifebase', 'Kalyptorhynchia Incertae sedis', 'discere:order:3'),
    ('discere:family:5', '5', 'sealifebase', 'Incertae sedis (Paratanaoidea)', 'discere:order:3'),
    ('discere:family:6', '6', 'sealifebase', 'Incertae sedis (Lysianassoidea', 'discere:order:3'),
    ('discere:family:7', '7', 'sealifebase', 'Chromodorididae', 'discere:order:3'),
    ('discere:family:8', '8', 'sealifebase', 'Sedisidae', 'discere:order:3');
INSERT INTO genera (id, external_id, external_source, name, family, is_placeholder) VALUES
    ('discere:genus:1', '1', 'sealifebase', 'Kynaria', 'discere:family:1', 0),
    ('discere:genus:2', '2', 'sealifebase', 'Incertasquilla', 'discere:family:7', 0),
    ('discere:genus:3', '3', 'sealifebase', 'Osedax', 'discere:family:7', 0),
    -- Aus einem Vorgänger mit anderer Regel übernommen: trägt noch das Flag.
    ('discere:genus:4', '4', 'sealifebase', 'Notassignia', 'discere:family:7', 1);
INSERT INTO species (id, external_id, external_source, name, genus, status) VALUES
    ('discere:species:1', '1', 'sealifebase', 'cynara', 'discere:genus:1', 'active'),
    ('discere:species:2', '2', 'sealifebase', 'alba', 'discere:genus:1', 'active'),
    ('discere:species:3', '3', 'sealifebase', 'vetus', 'discere:genus:1', 'deprecated');
SQL
}

# Die Namen aller Zeilen eines Rangs mit gesetztem Flag, ohne umgebende
# Leerzeichen und sortiert, je Zeile einer.
flagged_names() {
    sqlite3 "$DB" "SELECT trim(name) FROM $1 WHERE is_placeholder = 1 ORDER BY trim(name);"
}

run_placeholders() {
    export DISCERE_REPORT_DIR="$TEST_TMP/report"
    run_capture "$ETL_DIR/core/placeholders.sh" --db "$DB"
    REPORT="$(tail -n +2 "$TEST_TMP/report/placeholders.tsv" 2> /dev/null || true)"
}

test_placeholders_marks_every_spelling_the_sources_use() {
    create_placeholder_db
    run_placeholders
    assert_status 0
    assert_eq "Incerate sedis (Dinoflagellata)
Incertae sedis (Nemertea)
Not assigned" "$(flagged_names classes)" "Klassen"
    assert_eq "Not assigned
not ASSIGNED" "$(flagged_names orders)" "Ordnungen"
    assert_eq "Incertae sedis
Incertae sedis (Lysianassoidea
Incertae sedis (Paratanaoidea)
Kalyptorhynchia Incertae sedis
Not assigned
Tetraphyllidea Incertae sedis" "$(flagged_names families)" "Familien"
}

test_placeholders_leaves_real_names_unmarked() {
    create_placeholder_db
    run_placeholders
    assert_status 0
    assert_eq "" "$(flagged_names genera)" "Gattungen"
    assert_eq "0|0|0" "$(sqlite3 "$DB" "SELECT
        (SELECT is_placeholder FROM classes WHERE name = 'Gastropoda'),
        (SELECT is_placeholder FROM orders WHERE name = 'Eupercaria/misc'),
        (SELECT is_placeholder FROM families WHERE name = 'Sedisidae');")" "echte Namen"
}

test_placeholders_report_lists_each_hit_with_its_active_species() {
    create_placeholder_db
    run_placeholders
    assert_status 0
    assert_contains "$REPORT" "placeholders	family	discere:family:1	Not assigned	sealifebase, aktive Arten: 2"
    assert_contains "$REPORT" "placeholders	class	discere:class:2	Incertae sedis (Nemertea)	sealifebase, aktive Arten: 0"
    assert_eq "11" "$(grep -c . <<< "$REPORT")" "Einträge"
    run_capture "$ETL_DIR/core/report_summary.sh" "$TEST_TMP/report"
    assert_eq "placeholders: class 3 family 6 order 2" "$OUT" "Zusammenfassung"
}
