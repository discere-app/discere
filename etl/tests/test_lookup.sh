#!/usr/bin/env bash
# Tests für species_name_lookup (core/lookup.sh, core/sql/rebuild_lookup.sql,
# core/sql/lookup_report.sql): Ein Name bekommt nur einen Eintrag, wenn er
# genau eine aktive Art meint.

# Legt unter $TEST_TMP/ref.db Arten mit diesen Namen an (P = bevorzugt,
# S = Synonym, M = falsch angewandt):
#
#   amphiprion ocellaris   P bei 1, S bei 2
#   amphiprion percula     P bei 2, S bei 5 (deprecated)
#   amphiprion clarkii     P bei 3 (fishbase) und P bei 4 (sealifebase)
#   amphiprion bicolor     S bei 1
#   amphiprion communis    S bei 2, ambiguous synonym bei 3
#   amphiprion melanopus   S bei 1, M bei 2
#   amphiprion vetus       M bei 1
#   amphiprion akallopisos S bei 1, laut fishbase Synonym zweier Arten
#                          (ambiguous_scientific_names; die zweite Zeile steht
#                          auf einer anderen Ebene und fehlt hier)
# Auch amphiprion ocellaris führt fishbase als Synonym zweier Arten.
create_lookup_db() {
    DB="$TEST_TMP/ref.db"
    "$ETL_DIR/core/create_db.sh" --output "$DB" > /dev/null 2>&1
    sqlite3 "$DB" << 'SQL'
INSERT INTO species (id, external_id, external_source, name, status) VALUES
    ('discere:species:1', '1', 'fishbase',    'ocellaris', 'active'),
    ('discere:species:2', '2', 'fishbase',    'percula',   'active'),
    ('discere:species:3', '3', 'fishbase',    'clarkii',   'active'),
    ('discere:species:4', '4', 'sealifebase', 'clarkii',   'active'),
    ('discere:species:5', '5', 'fishbase',    'vetus',     'deprecated');
INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
    ('discere:species:1', 'Amphiprion ocellaris', 'amphiprion ocellaris', 'valid', 'fishbase', 1),
    ('discere:species:2', 'Amphiprion ocellaris', 'amphiprion ocellaris', 'synonym', 'fishbase', 0),
    ('discere:species:2', 'Amphiprion percula', 'amphiprion percula', 'valid', 'fishbase', 1),
    ('discere:species:5', 'Amphiprion percula', 'amphiprion percula', 'synonym', 'fishbase', 0),
    ('discere:species:3', 'Amphiprion clarkii', 'amphiprion clarkii', 'valid', 'fishbase', 1),
    ('discere:species:4', 'Amphiprion clarkii', 'amphiprion clarkii', 'valid', 'sealifebase', 1),
    ('discere:species:1', 'Amphiprion bicolor', 'amphiprion bicolor', 'synonym', 'fishbase', 0),
    ('discere:species:2', 'Amphiprion communis', 'amphiprion communis', 'synonym', 'fishbase', 0),
    ('discere:species:3', 'Amphiprion communis', 'amphiprion communis', 'ambiguous synonym', 'fishbase', 0),
    ('discere:species:1', 'Amphiprion melanopus', 'amphiprion melanopus', 'synonym', 'fishbase', 0),
    ('discere:species:2', 'Amphiprion melanopus', 'amphiprion melanopus', 'misapplied name', 'fishbase', 0),
    ('discere:species:1', 'Amphiprion vetus', 'amphiprion vetus', 'misapplied name', 'fishbase', 0),
    ('discere:species:1', 'Amphiprion akallopisos', 'amphiprion akallopisos', 'synonym', 'fishbase', 0);
INSERT INTO ambiguous_scientific_names (normalized_name, source, species_count) VALUES
    ('amphiprion akallopisos', 'fishbase', 2),
    ('amphiprion ocellaris', 'fishbase', 2);
SQL
}

run_lookup() {
    export DISCERE_REPORT_DIR="$TEST_TMP/report"
    run_capture "$ETL_DIR/core/lookup.sh" --db "$DB"
    REPORT="$(tail -n +2 "$TEST_TMP/report/lookup.tsv" 2> /dev/null || true)"
}

lookup_rows() {
    sqlite3 -separator ' → ' "$DB" "SELECT normalized_name, species_id FROM species_name_lookup ORDER BY 1;"
}

# Bevorzugt bei genau einer Art schlägt Synonyme anderer Arten, auch wenn
# die Quelle den Namen mehrdeutig führt; ein Synonym genau einer aktiven Art
# löst auf, auch neben einem falsch angewandten Namen einer anderen.
# Mehrdeutige — auch laut ambiguous_scientific_names — und nur falsch
# angewandte Namen bleiben ohne Eintrag.
test_lookup_resolves_only_names_that_mean_exactly_one_species() {
    create_lookup_db
    run_lookup
    assert_status 0
    assert_eq "amphiprion bicolor → discere:species:1
amphiprion melanopus → discere:species:1
amphiprion ocellaris → discere:species:1
amphiprion percula → discere:species:2" "$(lookup_rows)" "Lookup"
}

# Der Bericht nennt jeden Namen ohne Eintrag mit allen Arten.
test_lookup_reports_names_without_entry() {
    create_lookup_db
    run_lookup
    assert_status 0
    assert_eq "lookup	ambiguous	amphiprion akallopisos	Amphiprion akallopisos	discere:species:1 synonym; fishbase: Synonym von 2 Arten
lookup	ambiguous	amphiprion clarkii	Amphiprion clarkii	discere:species:3 preferred, discere:species:4 preferred
lookup	ambiguous	amphiprion communis	Amphiprion communis	discere:species:2 synonym, discere:species:3 ambiguous synonym
lookup	misapplied	amphiprion vetus	Amphiprion vetus	discere:species:1" "$REPORT" "Bericht"
    assert_contains "$ERR" "ohne Eintrag: 3 mehrdeutig, 1 nur falsch angewandt"
}

# Die Validierung verlangt genau die eindeutig auflösbaren Namen, jeden auf
# seine Art: Ein Eintrag für einen mehrdeutigen Namen lässt sie ebenso
# scheitern wie einer auf eine andere Art.
test_lookup_validation_requires_exactly_the_unambiguous_names() {
    create_lookup_db
    run_lookup
    assert_eq "species_name_lookup (>= expected)|4|4|always
species_name_lookup (<= expected)|4|4|always
species_name_lookup (targets)|4|4|always" \
        "$(sqlite3 "$DB" < "$ETL_DIR/core/sql/validate.sql" | grep '^species_name_lookup')" "Validierung"
    sqlite3 "$DB" "INSERT INTO species_name_lookup VALUES ('amphiprion communis', 'discere:species:2');"
    assert_eq "species_name_lookup (>= expected)|5|4|always
species_name_lookup (<= expected)|4|5|always
species_name_lookup (targets)|4|4|always" \
        "$(sqlite3 "$DB" < "$ETL_DIR/core/sql/validate.sql" | grep '^species_name_lookup')" "Validierung mit Eintrag"
    sqlite3 "$DB" "DELETE FROM species_name_lookup WHERE normalized_name = 'amphiprion communis';
                   UPDATE species_name_lookup SET species_id = 'discere:species:2'
                   WHERE normalized_name = 'amphiprion ocellaris';"
    assert_eq "species_name_lookup (targets)|3|4|always" \
        "$(sqlite3 "$DB" < "$ETL_DIR/core/sql/validate.sql" | grep '^species_name_lookup (targets)')" \
        "Validierung mit falscher Art"
}
