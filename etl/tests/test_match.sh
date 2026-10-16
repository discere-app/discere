#!/usr/bin/env bash
# Tests für den Abgleich (core/match.sh, core/sql/match.sql)

# Gleicht die übergebenen Zeilen „record_key<TAB>rank<TAB>name“ ab und legt
# das Ergebnis ohne Kopfzeile in RESULT ab, die Berichtseinträge in REPORT.
match_lines() {
    printf 'record_key\trank\tname\n' > "$TEST_TMP/input.tsv"
    printf '%s\n' "$@" >> "$TEST_TMP/input.tsv"
    export DISCERE_REPORT_DIR="$TEST_TMP/report"
    run_capture bash -c '
        source "$1/core/plugin_api.sh"
        source "$1/core/match.sh"
        PLUGIN_SOURCE=testquelle
        match_records "$2" "$3/input.tsv" "$3/result.tsv"
    ' _ "$ETL_DIR" "$DB" "$TEST_TMP"
    RESULT="$(tail -n +2 "$TEST_TMP/result.tsv" 2> /dev/null || true)"
    REPORT="$(tail -n +2 "$TEST_TMP/report/testquelle.tsv" 2> /dev/null || true)"
}

# Die Ergebniszeile eines Datensatzes: entity_id, status, matched_by, detail
result_of() {
    echo "$RESULT" | awk -F '\t' -v key="$1" '$1 == key { print $4 "|" $5 "|" $6 "|" $7 }'
}

test_match_by_accepted_name() {
    create_mini_reference_db
    match_lines $'10\tspecies\tAmphiprion ocellaris'
    assert_status 0
    assert_eq "discere:fishbase_species:1|matched|name|" "$(result_of 10)" "Ergebnis"
    assert_eq "" "$REPORT" "Bericht"
}

test_match_ignores_case_and_surrounding_spaces() {
    create_mini_reference_db
    match_lines $'10\tspecies\t  amphiprion OCELLARIS '
    assert_eq "discere:fishbase_species:1|matched|name|" "$(result_of 10)" "Ergebnis"
}

test_match_by_synonym() {
    create_mini_reference_db
    match_lines $'11\tspecies\tAmphiprion bicolor'
    assert_eq "discere:fishbase_species:1|matched|synonym|" "$(result_of 11)" "Ergebnis"
}

test_match_reports_none() {
    create_mini_reference_db
    match_lines $'12\tspecies\tAmphiprion nemo'
    assert_eq "|none||" "$(result_of 12)" "Ergebnis"
    assert_eq "testquelle	none	12	Amphiprion nemo	" "$REPORT" "Bericht"
}

test_match_never_picks_among_several_entities() {
    create_mini_reference_db
    match_lines $'13\tspecies\tAmphiprion communis'
    assert_eq "|ambiguous||mehrere Entitäten: discere:fishbase_species:2, discere:fishbase_species:3" \
        "$(result_of 13)" "Ergebnis"
    assert_eq "testquelle	ambiguous	13	Amphiprion communis	mehrere Entitäten: discere:fishbase_species:2, discere:fishbase_species:3" \
        "$REPORT" "Bericht"
}

test_match_ignores_inactive_species() {
    create_mini_reference_db
    match_lines $'14\tspecies\tAmphiprion vetus'
    assert_eq "|none||" "$(result_of 14)" "Ergebnis"
}

test_match_higher_taxa_by_name_in_rank_table() {
    create_mini_reference_db
    match_lines \
        $'20\tgenus\tAmphiprion' \
        $'21\tfamily\tPomacentridae' \
        $'22\torder\tOvalentaria' \
        $'23\tclass\tTeleostei'
    assert_eq "discere:fishbase_genus:1|matched|name|" "$(result_of 20)" "Gattung"
    assert_eq "discere:fishbase_family:1|matched|name|" "$(result_of 21)" "Familie"
    assert_eq "discere:fishbase_order:1|matched|name|" "$(result_of 22)" "Ordnung"
    assert_eq "discere:fishbase_class:7|matched|name|" "$(result_of 23)" "Klasse"
}

test_match_respects_rank() {
    create_mini_reference_db
    match_lines $'24\tgenus\tPomacentridae' $'25\tspecies\tTeleostei'
    assert_eq "|none||" "$(result_of 24)" "Familienname als Gattung"
    assert_eq "|none||" "$(result_of 25)" "Klassenname als Art"
}

test_match_gives_entity_to_record_with_accepted_name() {
    create_mini_reference_db
    match_lines $'30\tspecies\tAmphiprion ocellaris' $'31\tspecies\tAmphiprion bicolor'
    assert_eq "discere:fishbase_species:1|matched|name|" "$(result_of 30)" "akzeptierter Name"
    assert_eq "|ambiguous||weitere Datensätze treffen discere:fishbase_species:1: 30" \
        "$(result_of 31)" "Synonym"
}

test_match_rejects_unknown_rank() {
    create_mini_reference_db
    match_lines $'40\tkingdom\tAnimalia'
    assert_status 1
    assert_contains "$ERR" "CHECK constraint failed"
    assert_contains "$ERR" "Abgleich fehlgeschlagen"
}

test_match_keeps_quotes_as_part_of_the_name() {
    create_mini_reference_db
    match_lines $'50\tgenus\t"Amphiprion"'
    assert_status 0
    assert_eq "testquelle	none	50	\"Amphiprion\"	" "$REPORT" "Bericht"
}

# Die Quelle führt den akzeptierten Namen von species:5 als eigenen Datensatz
# (der selbst mehrdeutig ist, weil er auch Synonym von species:6 ist). Ihr
# Datensatz unter dem Synonym meint damit ein anderes Taxon und darf
# species:5 nicht bekommen.
test_match_synonym_loses_to_record_with_accepted_name_even_if_ambiguous() {
    create_mini_reference_db
    match_lines $'60\tspecies\tAmphiprion frenatus' $'61\tspecies\tAmphiprion melanopus'
    assert_eq "|ambiguous||mehrere Entitäten: discere:fishbase_species:5, discere:fishbase_species:6" \
        "$(result_of 60)" "akzeptierter Name, zugleich Synonym"
    assert_eq "|ambiguous||weitere Datensätze treffen discere:fishbase_species:5: 60" \
        "$(result_of 61)" "Synonym"
}

# Amphiprion ocellaris ist der akzeptierte Name von species:1 und bei
# species:6 als falsch angewandt geführt. Ein falsch angewandter Name meint
# ein anderes Taxon und ist kein Kandidat.
test_match_ignores_misapplied_names() {
    create_mini_reference_db
    match_lines $'70\tspecies\tAmphiprion ocellaris'
    assert_eq "discere:fishbase_species:1|matched|name|" "$(result_of 70)" "Ergebnis"
    assert_eq "" "$REPORT" "Bericht"
}

# Ein Aufrufer, der nur gegen einen Teil der Entitäten abgleicht, legt
# match_candidate_names selbst an — und darf match.sql in derselben Sitzung
# mehrfach lesen.
test_match_uses_caller_candidates_and_runs_twice_in_one_session() {
    create_mini_reference_db
    run_capture sqlite3 "$DB" << SQL
.bail on
CREATE TEMP TABLE match_input AS SELECT '80' AS record_key, 'species' AS rank, 'Amphiprion communis' AS name;
CREATE TEMP TABLE match_candidate_names AS
SELECT 'species' AS rank, 'discere:fishbase_species:3' AS entity_id, 'amphiprion communis' AS normalized_name, 0 AS by_accepted_name;
.read $ETL_DIR/core/sql/match.sql
SELECT record_key, entity_id, status, matched_by FROM match_result;
DROP TABLE match_input;
DROP TABLE match_candidate_names;
CREATE TEMP TABLE match_input AS SELECT '81' AS record_key, 'species' AS rank, 'Amphiprion communis' AS name;
.read $ETL_DIR/core/sql/match.sql
SELECT record_key, entity_id, status FROM match_result;
SQL
    assert_status 0
    assert_eq "80|discere:fishbase_species:3|matched|synonym
81||ambiguous" "$OUT" "zwei Läufe"
}
