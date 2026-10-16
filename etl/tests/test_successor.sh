#!/usr/bin/env bash
# Tests für die Nachfolger in der Identitäts-Stage (core/sql/identity_successor.sql):
# Arten des Vorgängers, die keine Quelle mehr liefert, deren gültiger Name in
# diesem Build ein Name genau einer aktiven Art ist.
#
# Nutzt die Helfer aus test_identity.sh (create_identity_build_db,
# create_initial_release, run_identity, registered_id, entity_listing,
# identity_report); run.sh sourct alle Testdateien in dieselbe Shell.
#
# Der Vorgänger ist der Mini-Build aus test_identity.sh, ohne Vorgänger
# zugeordnet (Arten fishbase 2 → discere:species:1 Amphiprion ocellaris,
# fishbase 10 → :2 Amphiprion percula, sealifebase 1 → :3, sealifebase 6 → :4,
# Gattung Amphiprion → discere:genus:1), dazu die FishBase-Art 50
# Amphiprion vetus als discere:species:5. Der Build liefert Art 50 nicht.

create_successor_release() {
    local db="$1" status="${2:-active}"
    local active=1
    [[ "$status" == active ]] || active=0
    create_initial_release "$db"
    sqlite3 "$db" << SQL
INSERT INTO species (id, external_id, external_source, name, genus, status, deprecated_at) VALUES
    ('discere:species:5', '50', 'fishbase', 'vetus', 'discere:genus:1', '$status',
     CASE WHEN '$status' = 'deprecated' THEN 1000 END);
INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
    ('discere:species:5', 'Amphiprion vetus', 'amphiprion vetus', 'valid', 'fishbase', 1);
INSERT INTO common_names (entity_id, entity_type, language, name, source, is_preferred) VALUES
    ('discere:species:5', 'species', 'de', 'Alter Anemonenfisch', 'fishbase', 1);
INSERT INTO entity_source_keys (source, entity_type, external_id, entity_id, active) VALUES
    ('fishbase', 'species', '50', 'discere:species:5', $active);
SQL
}

# Fügt der Build-Art <provisional_id> den Namen Amphiprion vetus mit
# <name_status> hinzu.
add_vetus_name() {
    sqlite3 "$1" "INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred)
                  VALUES ('$2', 'Amphiprion vetus', 'amphiprion vetus', '$3', 'fishbase', 0);"
}

aliases() {
    sqlite3 "$1" "SELECT alias_id || ' → ' || entity_id FROM entity_aliases ORDER BY 1;"
}

# Art discere:species:5: Zeile, Namen, Schlüssel 50.
species_5_state() {
    sqlite3 "$1" "
        SELECT 'species:' || COALESCE((SELECT status FROM species WHERE id = 'discere:species:5'), '-');
        SELECT 'names:' || (SELECT COUNT(*) FROM species_scientific_names WHERE species_id = 'discere:species:5')
                 || '/' || (SELECT COUNT(*) FROM common_names WHERE entity_id = 'discere:species:5');
        SELECT 'key:' || entity_id || ':' || active FROM entity_source_keys
        WHERE source = 'fishbase' AND entity_type = 'species' AND external_id = '50';"
}

test_successor_via_synonym_becomes_alias_target() {
    create_successor_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    add_vetus_name "$TEST_TMP/build.db" 'discere:fishbase_species:10' synonym
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:species:5 → discere:species:2" "$(aliases "$TEST_TMP/build.db")" "Aliase"
    assert_eq "species:-
names:0/0
key:discere:species:5:0" "$(species_5_state "$TEST_TMP/build.db")" "alte Art"
    assert_eq "identity	successor	discere:species:5	Amphiprion vetus	Alias auf discere:species:2 Amphiprion percula" \
        "$(identity_report)" "Build-Bericht"
    assert_contains "$ERR" "species: 4 Entitäten — 0 neue IDs, 0 aus mehreren Quellen zusammengeführt, 0 aus dem Vorgänger übernommen"
    assert_contains "$ERR" "Nachfolger: 1 Arten ohne aktiven Schlüssel werden Alias ihres Nachfolgers, 0 bleiben mehrdeutig, 0 Aliase zurückgenommen"
}

# Kontrollfall: Derselbe Schlüssel mit neuem Namen ist dieselbe Art.
test_successor_not_needed_for_renamed_species_with_same_key() {
    create_successor_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" "
        INSERT INTO species (id, external_id, external_source, name, genus) VALUES
            ('discere:fishbase_species:50', '50', 'fishbase', 'novus', 'discere:fishbase_genus:1');
        INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
            ('discere:fishbase_species:50', 'Amphiprion novus', 'amphiprion novus', 'valid', 'fishbase', 1);"
    add_vetus_name "$TEST_TMP/build.db" 'discere:fishbase_species:10' synonym
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "" "$(aliases "$TEST_TMP/build.db")" "Aliase"
    assert_eq "discere:species:5|novus|active" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT id, name, status FROM species WHERE external_id = '50';")" "Art 50"
    assert_eq "discere:species:5" "$(registered_id "$TEST_TMP/build.db" fishbase species 50)" "Schlüssel"
    assert_eq "" "$(identity_report)" "Build-Bericht"
}

test_successor_with_new_key_and_same_valid_name() {
    create_successor_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" "
        INSERT INTO species (id, external_id, external_source, name, genus) VALUES
            ('discere:fishbase_species:60', '60', 'fishbase', 'vetus', 'discere:fishbase_genus:1');
        INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
            ('discere:fishbase_species:60', 'Amphiprion vetus', 'amphiprion vetus', 'valid', 'fishbase', 1);"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:species:6" "$(registered_id "$TEST_TMP/build.db" fishbase species 60)" "neuer Schlüssel"
    assert_eq "discere:species:5 → discere:species:6" "$(aliases "$TEST_TMP/build.db")" "Aliase"
    assert_eq "species:-
names:0/0
key:discere:species:5:0" "$(species_5_state "$TEST_TMP/build.db")" "alte Art"
}

test_successor_ambiguous_keeps_species_deprecated_and_reports() {
    create_successor_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    add_vetus_name "$TEST_TMP/build.db" 'discere:fishbase_species:2' synonym
    add_vetus_name "$TEST_TMP/build.db" 'discere:fishbase_species:10' 'ambiguous synonym'
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "" "$(aliases "$TEST_TMP/build.db")" "Aliase"
    assert_eq "species:deprecated
names:1/1
key:discere:species:5:0" "$(species_5_state "$TEST_TMP/build.db")" "alte Art"
    assert_eq "identity	successor_ambiguous	discere:species:5	Amphiprion vetus	mehrere Arten: discere:species:1 Amphiprion ocellaris, discere:species:2 Amphiprion percula" \
        "$(identity_report)" "Build-Bericht"
    assert_contains "$ERR" "Nachfolger: 0 Arten ohne aktiven Schlüssel werden Alias ihres Nachfolgers, 1 bleiben mehrdeutig"
}

test_successor_ignores_misapplied_name() {
    create_successor_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    add_vetus_name "$TEST_TMP/build.db" 'discere:fishbase_species:10' 'misapplied name'
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "" "$(aliases "$TEST_TMP/build.db")" "Aliase"
    assert_eq "species:deprecated
names:1/1
key:discere:species:5:0" "$(species_5_state "$TEST_TMP/build.db")" "alte Art"
    assert_eq "" "$(identity_report)" "Build-Bericht"
}

# Der Vorgänger führt den Alias discere:species:9 → discere:species:5. Nach
# dem Build zeigt er direkt auf den Nachfolger.
test_successor_redirects_predecessor_aliases_without_chain() {
    create_successor_release "$TEST_TMP/prev.db"
    sqlite3 "$TEST_TMP/prev.db" "INSERT INTO entity_aliases VALUES ('discere:species:9', 'discere:species:5');"
    create_identity_build_db "$TEST_TMP/build.db"
    add_vetus_name "$TEST_TMP/build.db" 'discere:fishbase_species:10' synonym
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:species:5 → discere:species:2
discere:species:9 → discere:species:2" "$(aliases "$TEST_TMP/build.db")" "Aliase"
}

test_successor_for_species_already_deprecated_in_predecessor() {
    create_successor_release "$TEST_TMP/prev.db" deprecated
    create_identity_build_db "$TEST_TMP/build.db"
    add_vetus_name "$TEST_TMP/build.db" 'discere:fishbase_species:10' synonym
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:species:5 → discere:species:2" "$(aliases "$TEST_TMP/build.db")" "Aliase"
    assert_eq "species:-
names:0/0
key:discere:species:5:0" "$(species_5_state "$TEST_TMP/build.db")" "alte Art"
}

# Der Nachfolger entsteht in diesem Build aus zwei Quellen; den Namen der
# alten Art führt nur die weniger gewichtige.
test_successor_found_through_contributing_row_of_merged_species() {
    create_successor_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" "
        INSERT INTO genera (id, external_id, external_source, name, family) VALUES
            ('discere:sealifebase_genus:8', '8', 'sealifebase', 'Amphiprion', 'discere:sealifebase_family:3');
        INSERT INTO species (id, external_id, external_source, name, genus) VALUES
            ('discere:sealifebase_species:7', '7', 'sealifebase', 'ocellaris', 'discere:sealifebase_genus:8');
        INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
            ('discere:sealifebase_species:7', 'Amphiprion ocellaris', 'amphiprion ocellaris', 'valid',   'sealifebase', 1),
            ('discere:sealifebase_species:7', 'Amphiprion vetus',     'amphiprion vetus',     'synonym', 'sealifebase', 0);"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:species:1" "$(registered_id "$TEST_TMP/build.db" sealifebase species 7)" "zusammengeführt"
    assert_eq "discere:species:5 → discere:species:1" "$(aliases "$TEST_TMP/build.db")" "Aliase"
}

# Im nächsten Build, der die Art weiter nicht liefert, bleibt alles stehen:
# Der Schlüssel zeigt inaktiv auf den Alias, der Alias auf den Nachfolger.
test_successor_survives_next_build() {
    create_successor_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/first.db"
    add_vetus_name "$TEST_TMP/first.db" 'discere:fishbase_species:10' synonym
    run_identity "$TEST_TMP/first.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    create_identity_build_db "$TEST_TMP/second.db"
    add_vetus_name "$TEST_TMP/second.db" 'discere:fishbase_species:10' synonym
    run_identity "$TEST_TMP/second.db" --previous-release "$TEST_TMP/first.db"
    assert_status 0
    assert_eq "discere:species:5 → discere:species:2" "$(aliases "$TEST_TMP/second.db")" "Aliase"
    assert_eq "species:-
names:0/0
key:discere:species:5:0" "$(species_5_state "$TEST_TMP/second.db")" "alte Art"
    assert_contains "$ERR" "Nachfolger: 0 Arten"
}

# Taucht der Schlüssel der ersetzten Art wieder auf, bekommt er seine ID
# zurück; er geht nicht still im Nachfolger auf, und der Alias entfällt.
test_successor_alias_withdrawn_when_key_returns() {
    create_successor_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/first.db"
    add_vetus_name "$TEST_TMP/first.db" 'discere:fishbase_species:10' synonym
    run_identity "$TEST_TMP/first.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    rm -rf "$TEST_TMP/report"
    create_identity_build_db "$TEST_TMP/second.db"
    add_vetus_name "$TEST_TMP/second.db" 'discere:fishbase_species:10' synonym
    sqlite3 "$TEST_TMP/second.db" "
        INSERT INTO species (id, external_id, external_source, name, genus) VALUES
            ('discere:fishbase_species:50', '50', 'fishbase', 'vetus', 'discere:fishbase_genus:1');
        INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
            ('discere:fishbase_species:50', 'Amphiprion vetus', 'amphiprion vetus', 'valid', 'fishbase', 1);"
    run_identity "$TEST_TMP/second.db" --previous-release "$TEST_TMP/first.db"
    assert_status 0
    assert_eq "" "$(aliases "$TEST_TMP/second.db")" "Aliase"
    assert_eq "species:active
names:1/0
key:discere:species:5:1" "$(species_5_state "$TEST_TMP/second.db")" "Art 50"
    assert_eq "discere:species:2|percula|active" "$(sqlite3 "$TEST_TMP/second.db" "
        SELECT id, name, status FROM species WHERE id = 'discere:species:2';")" "Nachfolger bleibt eigene Art"
    assert_eq "identity	successor_withdrawn	discere:species:5	Amphiprion vetus	Schlüssel wieder geliefert, Alias auf discere:species:2 zurückgenommen" \
        "$(identity_report)" "Build-Bericht"
    assert_contains "$ERR" "0 bleiben mehrdeutig, 1 Aliase zurückgenommen"
}

# Eine Gattung des Vorgängers ohne aktiven Schlüssel wird übernommen, auch
# wenn eine gleichnamige Gattung geliefert wird.
test_successor_never_for_higher_taxa() {
    create_successor_release "$TEST_TMP/prev.db"
    sqlite3 "$TEST_TMP/prev.db" "
        INSERT INTO genera (id, external_id, external_source, name, family) VALUES
            ('discere:genus:5', '60', 'fishbase', 'Vetusia', 'discere:family:1');
        INSERT INTO entity_source_keys VALUES ('fishbase', 'genus', '60', 'discere:genus:5', 1);"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" "INSERT INTO genera (id, external_id, external_source, name, family) VALUES
        ('discere:sealifebase_genus:9', '9', 'sealifebase', 'Vetusia', 'discere:sealifebase_family:3');"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:genus:5|fishbase|60
discere:genus:6|sealifebase|9" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT id, external_source, external_id FROM genera WHERE name = 'Vetusia' ORDER BY id;")" "Gattungen"
    assert_eq "" "$(aliases "$TEST_TMP/build.db")" "Aliase"
}

# Der Vorgänger führt noch IDs mit Quelle (wie refdb-v2). Die alte ID und die
# einmalig abgeleitete, auf die der inaktive Schlüssel zeigt, werden Aliase
# auf den Nachfolger.
test_successor_when_register_is_derived() {
    create_release_without_register "$TEST_TMP/prev.db"
    sqlite3 "$TEST_TMP/prev.db" "
        INSERT INTO species (id, external_id, external_source, name, genus) VALUES
            ('discere:fishbase_species:50', '50', 'fishbase', 'vetus', 'discere:fishbase_genus:1');"
    create_identity_build_db "$TEST_TMP/build.db"
    add_vetus_name "$TEST_TMP/build.db" 'discere:fishbase_species:10' synonym
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:species:3" "$(registered_id "$TEST_TMP/build.db" fishbase species 50)" "abgeleitete ID"
    assert_eq "discere:fishbase_species:10 → discere:species:2
discere:fishbase_species:50 → discere:species:2
discere:species:3 → discere:species:2" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT alias_id || ' → ' || entity_id FROM entity_aliases
        WHERE entity_id = 'discere:species:2' ORDER BY 1;")" "Aliase"
    assert_eq "0" "$(sqlite3 "$TEST_TMP/build.db" "SELECT active FROM entity_source_keys
        WHERE source = 'fishbase' AND entity_type = 'species' AND external_id = '50';")" "Schlüssel inaktiv"
    assert_eq "identity	successor	discere:fishbase_species:50	Amphiprion vetus	Alias auf discere:species:2 Amphiprion percula" \
        "$(identity_report)" "Build-Bericht"
}

test_successor_assignment_is_deterministic() {
    create_successor_release "$TEST_TMP/prev.db"
    sqlite3 "$TEST_TMP/prev.db" "
        INSERT INTO species (id, external_id, external_source, name, genus, status) VALUES
            ('discere:species:6', '51', 'fishbase', 'antiqua', 'discere:genus:1', 'active');
        INSERT INTO entity_source_keys VALUES ('fishbase', 'species', '51', 'discere:species:6', 1);"
    local db
    for db in first second; do
        rm -rf "$TEST_TMP/report"
        create_identity_build_db "$TEST_TMP/$db.db"
        add_vetus_name "$TEST_TMP/$db.db" 'discere:fishbase_species:10' synonym
        sqlite3 "$TEST_TMP/$db.db" "
            INSERT INTO species (id, external_id, external_source, name, genus) VALUES
                ('discere:fishbase_species:61', '61', 'fishbase', 'antiqua', 'discere:fishbase_genus:1');
            INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
                ('discere:fishbase_species:61', 'Amphiprion antiqua', 'amphiprion antiqua', 'valid', 'fishbase', 1);"
        run_identity "$TEST_TMP/$db.db" --previous-release "$TEST_TMP/prev.db"
        assert_status 0
        identity_report > "$TEST_TMP/$db.report"
    done
    local dump="SELECT * FROM entity_source_keys ORDER BY 1, 2, 3; SELECT * FROM entity_aliases ORDER BY 1;"
    assert_eq "$(sqlite3 "$TEST_TMP/first.db" "$dump")" "$(sqlite3 "$TEST_TMP/second.db" "$dump")" "Register und Aliase"
    assert_eq "$(entity_listing "$TEST_TMP/first.db")" "$(entity_listing "$TEST_TMP/second.db")" "Entitäten"
    assert_eq "$(cat "$TEST_TMP/first.report")" "$(cat "$TEST_TMP/second.report")" "Build-Bericht"
    assert_eq "discere:species:5 → discere:species:2
discere:species:6 → discere:species:7" "$(aliases "$TEST_TMP/first.db")" "Aliase"
}
