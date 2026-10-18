#!/usr/bin/env bash
# Tests für die Identitäts-Stage (core/identity.sh) mit Mini-DBs als Build
# und als vorigem Release

# Legt unter <db> die Ausgabe der Plugins eines kleinen Builds an, mit
# vorläufigen IDs, und die Manifeste der beiden Quellen unter
# $TEST_TMP/plugins:
#
#   fishbase (placement_priority 10)
#     Klasse 7 Teleostei › Ordnung 1 Ovalentaria › Familie 1 Pomacentridae
#     › Gattung 1 Amphiprion: Arten 2 ocellaris, 10 percula
#     › Gattung 3 Gobio
#   sealifebase (placement_priority 20)
#     Klasse 1 Malacostraca › Ordnung 2 Decapoda › Familie 3 Nephropidae
#     › Gattung 4 Homarus: Art 1 gammarus
#     › Gattung 5 Gobio
#     Art 6 incertus ohne Gattung (leerer Verweis, wie ihn der CSV-Import
#     der Plugins schreibt)
#
# Dazu Beiträge an fishbase_species:2 (Volksname, Merkmal, Verbreitung, Bild,
# iNaturalist-ID), ein Namensschlüssel genus:amphiprion und Verbreitungsdaten
# zu einer Art 999, die keine Quelle liefert.
create_identity_build_db() {
    local db="$1"
    # Die Fälle lassen Arten des Vorgängers absichtlich fehlen, bei wenigen
    # Arten weit über der Default-Schwelle; den Einbruch einer Quelle prüfen
    # eigene Fälle (test_identity_aborts_when_a_source_loses_species …).
    make_plugin "$TEST_TMP/plugins" fishbase 'placement_priority: 10' 'species_loss_limit_percent: 100'
    make_plugin "$TEST_TMP/plugins" sealifebase 'placement_priority: 20' 'species_loss_limit_percent: 100'
    "$ETL_DIR/core/create_db.sh" --output "$db" > /dev/null 2>&1
    sqlite3 "$db" << 'SQL'
INSERT INTO classes (id, external_id, external_source, name, super_class) VALUES
    ('discere:fishbase_class:7',    '7', 'fishbase',    'Teleostei',    'Actinopterygii'),
    ('discere:sealifebase_class:1', '1', 'sealifebase', 'Malacostraca', 'Arthropoda');
INSERT INTO orders (id, external_id, external_source, name, class) VALUES
    ('discere:fishbase_order:1',    '1', 'fishbase',    'Ovalentaria', 'discere:fishbase_class:7'),
    ('discere:sealifebase_order:2', '2', 'sealifebase', 'Decapoda',    'discere:sealifebase_class:1');
INSERT INTO families (id, external_id, external_source, name, "order") VALUES
    ('discere:fishbase_family:1',    '1', 'fishbase',    'Pomacentridae', 'discere:fishbase_order:1'),
    ('discere:sealifebase_family:3', '3', 'sealifebase', 'Nephropidae',   'discere:sealifebase_order:2');
INSERT INTO genera (id, external_id, external_source, name, family) VALUES
    ('discere:fishbase_genus:1',    '1', 'fishbase',    'Amphiprion', 'discere:fishbase_family:1'),
    ('discere:fishbase_genus:3',    '3', 'fishbase',    'Gobio',      'discere:fishbase_family:1'),
    ('discere:sealifebase_genus:4', '4', 'sealifebase', 'Homarus',    'discere:sealifebase_family:3'),
    ('discere:sealifebase_genus:5', '5', 'sealifebase', 'Gobio',      'discere:sealifebase_family:3');
INSERT INTO species (id, external_id, external_source, name, genus, status) VALUES
    ('discere:fishbase_species:2',    '2',  'fishbase',    'ocellaris', 'discere:fishbase_genus:1',    'active'),
    ('discere:fishbase_species:10',   '10', 'fishbase',    'percula',   'discere:fishbase_genus:1',    'active'),
    ('discere:sealifebase_species:1', '1',  'sealifebase', 'gammarus',  'discere:sealifebase_genus:4', 'active'),
    ('discere:sealifebase_species:6', '6',  'sealifebase', 'incertus',  '',                            'active');
INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
    ('discere:fishbase_species:2',    'Amphiprion ocellaris', 'amphiprion ocellaris', 'valid', 'fishbase',    1),
    ('discere:fishbase_species:10',   'Amphiprion percula',   'amphiprion percula',   'valid', 'fishbase',    1),
    ('discere:sealifebase_species:1', 'Homarus gammarus',     'homarus gammarus',     'valid', 'sealifebase', 1);
INSERT INTO common_names (entity_id, entity_type, language, name, source, is_preferred) VALUES
    ('discere:fishbase_species:2', 'species', 'en', 'Clown anemonefish', 'fishbase', 1),
    ('discere:fishbase_genus:1',   'genus',   'en', 'anemonefishes',     'fishbase', 1);
INSERT INTO taxonomy_traits (entity_id, entity_type, trait_key, trait_value_bool, source) VALUES
    ('discere:fishbase_species:2', 'species', 'reef_association', 1, 'fishbase');
INSERT INTO taxonomy_distribution_regions (entity_id, entity_type, source, region_scope, region_key, region_label) VALUES
    ('discere:fishbase_species:2',   'species', 'fishbase', 'country', '276', '276'),
    ('discere:fishbase_species:999', 'species', 'fishbase', 'country', '276', '276');
INSERT INTO pictures (id, species, url, origin) VALUES
    ('discere:fishbase_pic:2:a.jpg', 'discere:fishbase_species:2', 'https://example.org/a.jpg', 'fishbase');
INSERT INTO entity_external_ids (entity_id, entity_type, provider, external_id) VALUES
    ('discere:fishbase_species:2', 'species', 'inaturalist', '100'),
    ('genus:amphiprion',           'genera',  'inaturalist', '200');
SQL
}

run_identity() {
    local db="$1"
    shift
    export DISCERE_REPORT_DIR="$TEST_TMP/report"
    run_capture "$ETL_DIR/core/identity.sh" --db "$db" --plugins-dir "$TEST_TMP/plugins" "$@"
}

# Ein Release wie refdb-v2: vorläufige IDs mit Quelle, ohne Register und
# Aliase.
create_release_without_register() {
    local db="$1"
    create_identity_build_db "$db"
    sqlite3 "$db" "DROP TABLE entity_source_keys; DROP TABLE entity_aliases;"
}

# Ein Release mit Register: der Mini-Build, ohne Vorgänger zugeordnet.
create_initial_release() {
    local db="$1"
    create_identity_build_db "$db"
    run_identity "$db" --initial
    assert_status 0
}

registered_id() {
    sqlite3 "$1" "SELECT entity_id FROM entity_source_keys
                  WHERE source = '$2' AND entity_type = '$3' AND external_id = '$4';"
}

# Je Zeile Typ, Quelle, external_id und ID aller Entitäten.
entity_listing() {
    sqlite3 -separator ' ' "$1" "
        SELECT 'species', external_source, external_id, id FROM species
        UNION ALL SELECT 'genus',  external_source, external_id, id FROM genera
        UNION ALL SELECT 'family', external_source, external_id, id FROM families
        UNION ALL SELECT 'order',  external_source, external_id, id FROM orders
        UNION ALL SELECT 'class',  external_source, external_id, id FROM classes
        ORDER BY 1, 2, 3;"
}

identity_report() {
    tail -n +2 "$TEST_TMP/report/identity.tsv" 2> /dev/null || true
}

test_identity_initial_numbers_from_one_in_key_order() {
    create_identity_build_db "$TEST_TMP/build.db"
    run_identity "$TEST_TMP/build.db" --initial
    assert_status 0
    assert_contains "$ERR" "--initial: ohne Vorgänger, alle IDs werden neu vergeben"
    assert_eq "class fishbase 7 discere:class:1
class sealifebase 1 discere:class:2
family fishbase 1 discere:family:1
family sealifebase 3 discere:family:2
genus fishbase 1 discere:genus:1
genus fishbase 3 discere:genus:2
genus sealifebase 4 discere:genus:3
genus sealifebase 5 discere:genus:4
order fishbase 1 discere:order:1
order sealifebase 2 discere:order:2
species fishbase 10 discere:species:2
species fishbase 2 discere:species:1
species sealifebase 1 discere:species:3
species sealifebase 6 discere:species:4" "$(entity_listing "$TEST_TMP/build.db")" "Entitäten"
    assert_eq "14|14|0" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT COUNT(*), SUM(active), (SELECT COUNT(*) FROM entity_aliases) FROM entity_source_keys;")" \
        "Schlüssel, aktiv, Aliase"
}

test_identity_keeps_same_named_higher_taxa_of_two_sources_apart() {
    create_identity_build_db "$TEST_TMP/build.db"
    run_identity "$TEST_TMP/build.db" --initial
    assert_status 0
    assert_eq "discere:genus:2|fishbase
discere:genus:4|sealifebase" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT id, external_source FROM genera WHERE name = 'Gobio' ORDER BY id;")" "Gattungen Gobio"
}

test_identity_derives_register_and_aliases_from_release_without_register() {
    create_release_without_register "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" "INSERT INTO species (id, external_id, external_source, name, genus) VALUES
        ('discere:fishbase_species:11', '11', 'fishbase', 'clarkii', 'discere:fishbase_genus:1');"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_contains "$ERR" "ohne Register — wird einmalig aus seinen IDs abgeleitet"
    assert_eq "discere:species:1" "$(registered_id "$TEST_TMP/build.db" fishbase species 2)" "fishbase 2"
    assert_eq "discere:species:3" "$(registered_id "$TEST_TMP/build.db" sealifebase species 1)" "sealifebase 1"
    assert_eq "discere:species:5" "$(registered_id "$TEST_TMP/build.db" fishbase species 11)" "neue Art"
    assert_eq "14" "$(sqlite3 "$TEST_TMP/build.db" "SELECT COUNT(*) FROM entity_aliases;")" "Aliase"
    assert_eq "discere:species:1
discere:genus:4
discere:class:1" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT entity_id FROM entity_aliases WHERE alias_id = 'discere:fishbase_species:2';
        SELECT entity_id FROM entity_aliases WHERE alias_id = 'discere:sealifebase_genus:5';
        SELECT entity_id FROM entity_aliases WHERE alias_id = 'discere:fishbase_class:7';")" "Alias → neue ID"
}

test_identity_known_keys_keep_their_ids() {
    create_initial_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_contains "$ERR" "(mit Register)"
    assert_eq "$(entity_listing "$TEST_TMP/prev.db")" "$(entity_listing "$TEST_TMP/build.db")" "Entitäten"
    assert_eq "0" "$(sqlite3 "$TEST_TMP/build.db" "SELECT COUNT(*) FROM entity_aliases;")" "Aliase"
}

# Die größte Nummer kommt auch aus den Aliasen: Eine Nummer, die einmal
# vergeben war, wird nie wieder vergeben.
test_identity_new_key_gets_next_unused_number() {
    create_initial_release "$TEST_TMP/prev.db"
    sqlite3 "$TEST_TMP/prev.db" "INSERT INTO entity_aliases VALUES ('discere:species:9', 'discere:species:1');"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" "INSERT INTO species (id, external_id, external_source, name, genus) VALUES
        ('discere:fishbase_species:11', '11', 'fishbase', 'clarkii', 'discere:fishbase_genus:1');"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:species:10" "$(registered_id "$TEST_TMP/build.db" fishbase species 11)" "neue Art"
    assert_eq "discere:species:9|discere:species:1" \
        "$(sqlite3 "$TEST_TMP/build.db" "SELECT * FROM entity_aliases;")" "Alias übernommen"
}

test_identity_assignment_is_deterministic() {
    create_release_without_register "$TEST_TMP/prev.db"
    local db
    for db in first second; do
        create_identity_build_db "$TEST_TMP/$db.db"
        sqlite3 "$TEST_TMP/$db.db" "INSERT INTO species (id, external_id, external_source, name, genus) VALUES
            ('discere:sealifebase_species:30', '30', 'sealifebase', 'americanus', 'discere:sealifebase_genus:4'),
            ('discere:fishbase_species:11',    '11', 'fishbase',    'clarkii',    'discere:fishbase_genus:1');"
        run_identity "$TEST_TMP/$db.db" --previous-release "$TEST_TMP/prev.db"
        assert_status 0
    done
    local dump="SELECT * FROM entity_source_keys ORDER BY 1, 2, 3; SELECT * FROM entity_aliases ORDER BY 1;"
    assert_eq "$(entity_listing "$TEST_TMP/first.db")" "$(entity_listing "$TEST_TMP/second.db")" "Entitäten"
    assert_eq "$(sqlite3 "$TEST_TMP/first.db" "$dump")" "$(sqlite3 "$TEST_TMP/second.db" "$dump")" "Register und Aliase"
    assert_eq "discere:species:5
discere:species:6" "$(sqlite3 "$TEST_TMP/first.db" "
        SELECT entity_id FROM entity_source_keys WHERE external_id IN ('11', '30') AND entity_type = 'species'
        ORDER BY source;")" "neue Arten nach Quelle"
}

# Eine neue SeaLifeBase-Art trifft eine FishBase-Art mit eigenem Schlüssel:
# dieselbe Entität. Die FishBase-Zeile gilt samt Einordnung, die Beiträge der
# SeaLifeBase-Zeile hängen an der gemeinsamen ID; wo beide denselben
# Schlüssel belegen (eine iNaturalist-ID je Art), bleibt der FishBase-Beitrag.
test_identity_merges_species_of_two_sources() {
    create_initial_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" << 'SQL'
INSERT INTO families (id, external_id, external_source, name, "order") VALUES
    ('discere:sealifebase_family:9', '9', 'sealifebase', 'Pomacentridae', 'discere:sealifebase_order:2');
INSERT INTO genera (id, external_id, external_source, name, family) VALUES
    ('discere:sealifebase_genus:8', '8', 'sealifebase', 'Amphiprion', 'discere:sealifebase_family:9');
INSERT INTO species (id, external_id, external_source, name, genus) VALUES
    ('discere:sealifebase_species:7', '7', 'sealifebase', 'ocellaris', 'discere:sealifebase_genus:8');
INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
    ('discere:sealifebase_species:7', 'Amphiprion ocellaris', 'amphiprion ocellaris', 'valid', 'sealifebase', 1);
INSERT INTO common_names (entity_id, entity_type, language, name, source, is_preferred) VALUES
    ('discere:sealifebase_species:7', 'species', 'en', 'Clownfish', 'sealifebase', 1);
INSERT INTO pictures (id, species, url, origin) VALUES
    ('discere:sealifebase_pic:7:b.jpg', 'discere:sealifebase_species:7', 'https://example.org/b.jpg', 'sealifebase');
INSERT INTO taxonomy_distribution_regions (entity_id, entity_type, source, region_scope, region_key, region_label) VALUES
    ('discere:sealifebase_species:7', 'species', 'sealifebase', 'country', '250', '250');
INSERT INTO entity_external_ids (entity_id, entity_type, provider, external_id) VALUES
    ('discere:sealifebase_species:7', 'species', 'inaturalist', '101');
SQL
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:species:1" "$(registered_id "$TEST_TMP/build.db" sealifebase species 7)" "Schlüssel auf bestehender ID"
    assert_eq "discere:species:1" "$(registered_id "$TEST_TMP/build.db" fishbase species 2)" "FishBase-Schlüssel"
    assert_eq "discere:species:1|fishbase|2|discere:genus:1" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT id, external_source, external_id, genus FROM species WHERE name = 'ocellaris';")" "Zeile der Art"
    assert_eq "Clown anemonefish fishbase
Clownfish sealifebase" "$(sqlite3 -separator ' ' "$TEST_TMP/build.db" "
        SELECT name, source FROM common_names WHERE entity_id = 'discere:species:1' ORDER BY name;")" "Volksnamen"
    assert_eq "2|2|2" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT (SELECT COUNT(*) FROM species_scientific_names WHERE species_id = 'discere:species:1'),
               (SELECT COUNT(*) FROM pictures WHERE species = 'discere:species:1'),
               (SELECT COUNT(*) FROM taxonomy_distribution_regions WHERE entity_id = 'discere:species:1');")" \
        "Namen, Bilder, Verbreitung"
    assert_eq "100" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT GROUP_CONCAT(external_id) FROM entity_external_ids WHERE entity_id = 'discere:species:1';")" "iNaturalist-ID"
    assert_eq "identity	placement	sealifebase:species:7	Amphiprion ocellaris	gilt fishbase: Amphiprion › Pomacentridae › Ovalentaria › Teleostei; sealifebase: Amphiprion › Pomacentridae › Decapoda › Malacostraca" \
        "$(identity_report)" "Build-Bericht"
    assert_contains "$ERR" "species: 4 Entitäten — 0 neue IDs, 1 aus mehreren Quellen zusammengeführt"
}

# Liefert die gewichtigere Quelle eine Art neu, die eine andere schon führt,
# bleibt die ID, und die Zeile kommt von der gewichtigeren Quelle.
test_identity_merged_species_takes_row_of_weightier_source() {
    create_initial_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" << 'SQL'
INSERT INTO genera (id, external_id, external_source, name, family) VALUES
    ('discere:fishbase_genus:13', '13', 'fishbase', 'Homarus', 'discere:fishbase_family:1');
INSERT INTO species (id, external_id, external_source, name, genus) VALUES
    ('discere:fishbase_species:12', '12', 'fishbase', 'gammarus', 'discere:fishbase_genus:13');
INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
    ('discere:fishbase_species:12', 'Homarus gammarus', 'homarus gammarus', 'valid', 'fishbase', 1);
SQL
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:species:3|fishbase|12|discere:genus:5" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT id, external_source, external_id, genus FROM species WHERE name = 'gammarus';")" "Zeile der Art"
    assert_eq "discere:species:3" "$(registered_id "$TEST_TMP/build.db" fishbase species 12)" "FishBase-Schlüssel"
}

test_identity_reports_ambiguous_match_and_creates_new_species() {
    create_initial_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" << 'SQL'
INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
    ('discere:fishbase_species:2',  'Amphiprion communis', 'amphiprion communis', 'synonym', 'fishbase', 0),
    ('discere:fishbase_species:10', 'Amphiprion communis', 'amphiprion communis', 'synonym', 'fishbase', 0);
INSERT INTO species (id, external_id, external_source, name, genus) VALUES
    ('discere:sealifebase_species:7', '7', 'sealifebase', 'communis', 'discere:sealifebase_genus:8');
INSERT INTO genera (id, external_id, external_source, name, family) VALUES
    ('discere:sealifebase_genus:8', '8', 'sealifebase', 'Amphiprion', 'discere:sealifebase_family:3');
SQL
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:species:5" "$(registered_id "$TEST_TMP/build.db" sealifebase species 7)" "neue Art"
    assert_eq "identity	ambiguous	sealifebase:species:7	Amphiprion communis	mehrere Entitäten: discere:species:1, discere:species:2" \
        "$(identity_report)" "Build-Bericht"
}

# Der Vorgänger führt FishBase-Art 50 (Gattung 60) und die schon
# veraltete Art 51; keine Quelle liefert sie mehr.
test_identity_carries_over_species_without_active_key() {
    create_initial_release "$TEST_TMP/prev.db"
    sqlite3 "$TEST_TMP/prev.db" << 'SQL'
INSERT INTO genera (id, external_id, external_source, name, family) VALUES
    ('discere:genus:5', '60', 'fishbase', 'Vetusia', 'discere:family:1');
INSERT INTO species (id, external_id, external_source, name, genus, status, deprecated_at) VALUES
    ('discere:species:5', '50', 'fishbase', 'vetus',  'discere:genus:5', 'active',     NULL),
    ('discere:species:6', '51', 'fishbase', 'antiqua', 'discere:genus:1', 'deprecated', 1000);
INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
    ('discere:species:5', 'Vetusia vetus', 'vetusia vetus', 'valid', 'fishbase', 1);
INSERT INTO common_names (entity_id, entity_type, language, name, source, is_preferred) VALUES
    ('discere:species:5', 'species', 'de', 'Alter Fisch', 'fishbase', 1);
INSERT INTO entity_source_keys (source, entity_type, external_id, entity_id, active) VALUES
    ('fishbase', 'genus',   '60', 'discere:genus:5',   1),
    ('fishbase', 'species', '50', 'discere:species:5', 1),
    ('fishbase', 'species', '51', 'discere:species:6', 0);
SQL
    create_identity_build_db "$TEST_TMP/build.db"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:species:5|vetus|discere:genus:5|deprecated|1
discere:species:6|antiqua|discere:genus:1|deprecated|1000" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT id, name, genus, status, CASE WHEN deprecated_at > 1000 THEN 1 ELSE deprecated_at END
        FROM species WHERE external_id IN ('50', '51') ORDER BY id;")" "übernommene Arten"
    assert_eq "Vetusia|discere:family:1" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT name, family FROM genera WHERE id = 'discere:genus:5';")" "übernommene Gattung"
    assert_eq "Vetusia vetus|Alter Fisch" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT (SELECT name FROM species_scientific_names WHERE species_id = 'discere:species:5'),
               (SELECT name FROM common_names WHERE entity_id = 'discere:species:5');")" "Namen"
    assert_eq "fishbase genus 60 0
fishbase species 50 0
fishbase species 51 0" "$(sqlite3 -separator ' ' "$TEST_TMP/build.db" "
        SELECT source, entity_type, external_id, active FROM entity_source_keys
        WHERE external_id IN ('50', '51', '60') ORDER BY 2, 3;")" "Schlüssel inaktiv"
    assert_contains "$ERR" "species: 6 Entitäten — 0 neue IDs, 0 aus mehreren Quellen zusammengeführt, 2 aus dem Vorgänger übernommen"
}

# Bilder einer übernommenen Art kommen mit. Der Build liefert eins davon
# noch, aber ohne Art (die Quelle führt die Art 50 nicht mehr): Es weicht dem
# übernommenen.
test_identity_carries_over_pictures_of_species_without_active_key() {
    create_initial_release "$TEST_TMP/prev.db"
    sqlite3 "$TEST_TMP/prev.db" << 'SQL'
INSERT INTO species (id, external_id, external_source, name, genus, status) VALUES
    ('discere:species:5', '50', 'fishbase', 'vetus', 'discere:genus:1', 'active');
INSERT INTO entity_source_keys (source, entity_type, external_id, entity_id, active) VALUES
    ('fishbase', 'species', '50', 'discere:species:5', 1);
INSERT INTO pictures (id, species, url, origin, license_key, is_usable) VALUES
    ('discere:fishbase_pic:50:v1.jpg', 'discere:species:5', 'https://example.org/v1.jpg', 'fishbase', 'CC BY 4.0', 1),
    ('discere:fishbase_pic:50:v2.jpg', 'discere:species:5', 'https://example.org/v2.jpg', 'fishbase', 'ARR', 0);
SQL
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" "INSERT INTO pictures (id, species, url, origin) VALUES
        ('discere:fishbase_pic:50:v2.jpg', '', 'https://example.org/v2-neu.jpg', 'fishbase');"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:fishbase_pic:2:a.jpg|discere:species:1|https://example.org/a.jpg|0
discere:fishbase_pic:50:v1.jpg|discere:species:5|https://example.org/v1.jpg|1
discere:fishbase_pic:50:v2.jpg|discere:species:5|https://example.org/v2.jpg|0" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT id, species, url, is_usable FROM pictures ORDER BY id;")" "Bilder"
    assert_contains "$ERR" "Bilder übernommener Arten: 2"
    assert_contains "$ERR" "Bilder ohne Art durch übernommene ersetzt: 1"
}

# Höhere Taxa ordnet die Stage allein über den Schlüssel zu. Liefert ein
# bekannter Schlüssel ein Taxon anderen Namens — etwa weil die Quelle den
# Code zweimal vergibt und der Export die andere Zeile wählt —, bekäme die ID
# ein anderes Taxon: Abbruch, ohne etwas zu schreiben.
test_identity_aborts_when_known_higher_taxon_key_names_another_taxon() {
    create_initial_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" "
        UPDATE orders SET name = 'Araneae' WHERE id = 'discere:sealifebase_order:2';
        UPDATE genera SET name = 'Gobius' WHERE id = 'discere:fishbase_genus:3';"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 1
    assert_contains "$ERR" "Identität: 2 Schlüssel höherer Taxa nennen ein anderes Taxon als im Vorgänger (Typ Quelle:Schlüssel Vorgänger → jetzt): genus fishbase:3 Gobio → Gobius; order sealifebase:2 Decapoda → Araneae"
    assert_eq "0" "$(sqlite3 "$TEST_TMP/build.db" "SELECT COUNT(*) FROM entity_source_keys;")" "nichts geschrieben"
}

# Gleichnamige Taxa unterscheidet der Name nicht: Hängt eine Ordnung unter
# dem Schlüssel einer anderen Klasse oder eine Familie unter dem einer
# anderen Ordnung als im Vorgänger, Abbruch.
test_identity_aborts_when_known_key_moves_to_another_parent_key() {
    create_initial_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" "
        INSERT INTO classes (id, external_id, external_source, name, super_class) VALUES
            ('discere:sealifebase_class:5', '5', 'sealifebase', 'Hexanauplia', 'Arthropoda');
        INSERT INTO orders (id, external_id, external_source, name, class) VALUES
            ('discere:fishbase_order:9', '9', 'fishbase', 'Gobiiformes', 'discere:fishbase_class:7');
        UPDATE orders SET class = 'discere:sealifebase_class:5' WHERE id = 'discere:sealifebase_order:2';
        UPDATE families SET \"order\" = 'discere:fishbase_order:9' WHERE id = 'discere:fishbase_family:1';"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 1
    assert_contains "$ERR" "Identität: 2 Schlüssel von Ordnungen bzw. Familien hängen unter einem anderen Elternschlüssel als im Vorgänger (Typ Quelle:Schlüssel Name, Eltern Vorgänger → jetzt): family fishbase:1 Pomacentridae, 1 → 9; order sealifebase:2 Decapoda, 1 → 5"
    assert_eq "0" "$(sqlite3 "$TEST_TMP/build.db" "SELECT COUNT(*) FROM entity_source_keys;")" "nichts geschrieben"
}

# Hängt eine Familie unter einer anderen Ordnung als im Vorgänger, weil der
# Export sie nach einer Regel gezielt umgehängt hat (source_parent_overrides),
# ist das kein Wechsel des Taxons: Die Stage baut weiter.
test_identity_accepts_parent_change_listed_by_export() {
    create_initial_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" "
        INSERT INTO orders (id, external_id, external_source, name, class) VALUES
            ('discere:sealifebase_order:7', '7', 'sealifebase', 'Achelata', 'discere:sealifebase_class:1');
        UPDATE families SET \"order\" = 'discere:sealifebase_order:7' WHERE id = 'discere:sealifebase_family:3';
        INSERT INTO source_parent_overrides (source, entity_type, external_id, parent_external_id) VALUES
            ('sealifebase', 'family', '3', '7');"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "$(registered_id "$TEST_TMP/build.db" sealifebase order 7)" \
        "$(sqlite3 "$TEST_TMP/build.db" "SELECT \"order\" FROM families WHERE id = '$(registered_id "$TEST_TMP/build.db" sealifebase family 3)';")" \
        "Ordnung von Nephropidae"
}

# Zugelassen ist nur genau der Elternschlüssel, den der Export nennt, und nur
# für seine Quelle: Ein anderer Wechsel bricht weiter ab.
test_identity_aborts_on_parent_change_other_than_listed() {
    create_initial_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" "
        INSERT INTO orders (id, external_id, external_source, name, class) VALUES
            ('discere:sealifebase_order:7', '7', 'sealifebase', 'Achelata', 'discere:sealifebase_class:1'),
            ('discere:fishbase_order:9', '9', 'fishbase', 'Gobiiformes', 'discere:fishbase_class:7');
        UPDATE families SET \"order\" = 'discere:sealifebase_order:7' WHERE id = 'discere:sealifebase_family:3';
        UPDATE families SET \"order\" = 'discere:fishbase_order:9' WHERE id = 'discere:fishbase_family:1';
        INSERT INTO source_parent_overrides (source, entity_type, external_id, parent_external_id) VALUES
            ('sealifebase', 'family', '3', '8'),
            ('sealifebase', 'family', '1', '9');"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 1
    assert_contains "$ERR" "Identität: 2 Schlüssel von Ordnungen bzw. Familien hängen unter einem anderen Elternschlüssel als im Vorgänger (Typ Quelle:Schlüssel Name, Eltern Vorgänger → jetzt): family fishbase:1 Pomacentridae, 1 → 9; family sealifebase:3 Nephropidae, 2 → 7"
}

# Leerzeichen am Rand und Groß- und Kleinschreibung ändern das Taxon nicht,
# ebenso wenig ein anderes Epitheton einer Art unter gleichem Schlüssel oder
# eine Familie, die ihre Ordnung verliert.
test_identity_accepts_same_higher_taxon_name_in_other_spelling() {
    create_initial_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" "
        UPDATE orders SET name = ' decapoda' WHERE id = 'discere:sealifebase_order:2';
        UPDATE species SET name = 'ocellata' WHERE id = 'discere:fishbase_species:2';
        UPDATE families SET \"order\" = '' WHERE id = 'discere:sealifebase_family:3';"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
}

# Den Einbruch einer Quelle prüft die Default-Schwelle von 5 %: Die Manifeste
# verlieren die großzügige Schwelle von create_identity_build_db.
use_default_loss_limits() {
    make_plugin "$TEST_TMP/plugins" fishbase 'placement_priority: 10'
    make_plugin "$TEST_TMP/plugins" sealifebase 'placement_priority: 20'
}

# Der Vorgänger führt fishbase 2 und 10; der Build liefert 10 nicht mehr.
test_identity_aborts_when_a_source_loses_species() {
    create_initial_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    use_default_loss_limits
    sqlite3 "$TEST_TMP/build.db" "
        DELETE FROM species_scientific_names WHERE species_id = 'discere:fishbase_species:10';
        DELETE FROM species WHERE id = 'discere:fishbase_species:10';"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 1
    assert_contains "$ERR" "Identität: Arten-Rückgang über der Schwelle: fishbase 1 von 2 (50.0 %, erlaubt 5 %)."
    assert_eq "0" "$(sqlite3 "$TEST_TMP/build.db" "SELECT COUNT(*) FROM entity_source_keys;")" "nichts geschrieben"
}

test_identity_aborts_when_a_source_vanishes() {
    create_initial_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    use_default_loss_limits
    sqlite3 "$TEST_TMP/build.db" "DELETE FROM species WHERE external_source = 'sealifebase';"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 1
    assert_contains "$ERR" "sealifebase 2 von 2 (100.0 %, erlaubt 5 %)"
}

# Ein angenommener Rückgang und einer unter der Schwelle der Quelle bauen
# weiter; die Zusammenfassung nennt beide.
test_identity_builds_on_accepted_or_allowed_species_loss() {
    create_initial_release "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    use_default_loss_limits
    make_plugin "$TEST_TMP/plugins" sealifebase 'placement_priority: 20' 'species_loss_limit_percent: 50'
    sqlite3 "$TEST_TMP/build.db" "
        DELETE FROM species_scientific_names WHERE species_id = 'discere:fishbase_species:10';
        DELETE FROM species WHERE id IN ('discere:fishbase_species:10', 'discere:sealifebase_species:6');"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db" --accept-species-loss fishbase
    assert_status 0
    assert_contains "$ERR" "Arten des Vorgängers nicht mehr geliefert: fishbase 1 von 2 (50.0 %, erlaubt 5 %, Rückgang angenommen)"
    assert_contains "$ERR" "Arten des Vorgängers nicht mehr geliefert: sealifebase 1 von 2 (50.0 %, erlaubt 50 %)"
}

# Der Vorgänger führt noch IDs mit Quelle und einen Alias A → B. B wird in
# diesem Build zu C; A darf nicht auf B zeigen bleiben.
test_identity_aliases_follow_their_target() {
    create_release_without_register "$TEST_TMP/prev.db"
    sqlite3 "$TEST_TMP/prev.db" "
        CREATE TABLE entity_aliases (alias_id TEXT NOT NULL PRIMARY KEY, entity_id TEXT NOT NULL);
        INSERT INTO entity_aliases VALUES ('discere:fishbase_species:1', 'discere:fishbase_species:2');"
    create_identity_build_db "$TEST_TMP/build.db"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "discere:fishbase_species:1|discere:species:1
discere:fishbase_species:2|discere:species:1" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT * FROM entity_aliases WHERE alias_id IN ('discere:fishbase_species:1', 'discere:fishbase_species:2')
        ORDER BY 1;")" "Aliase"
}

test_identity_aborts_when_alias_id_is_an_entity() {
    create_initial_release "$TEST_TMP/prev.db"
    sqlite3 "$TEST_TMP/prev.db" "INSERT INTO entity_aliases VALUES ('discere:species:1', 'discere:species:2');"
    create_identity_build_db "$TEST_TMP/build.db"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 1
    assert_contains "$ERR" "Identität: Aliase: 1 Alias-IDs sind zugleich Entitäts-IDs, z. B. discere:species:1"
    assert_contains "$ERR" "Identitäts-Stage fehlgeschlagen"
}

test_identity_aborts_when_alias_points_nowhere() {
    create_initial_release "$TEST_TMP/prev.db"
    sqlite3 "$TEST_TMP/prev.db" "INSERT INTO entity_aliases VALUES ('discere:species:77', 'discere:species:99');"
    create_identity_build_db "$TEST_TMP/build.db"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 1
    assert_contains "$ERR" "Aliase: 1 zeigen auf keine Entität, z. B. discere:species:77 → discere:species:99"
}

test_identity_aborts_on_alias_chain() {
    create_initial_release "$TEST_TMP/prev.db"
    sqlite3 "$TEST_TMP/prev.db" "INSERT INTO entity_aliases VALUES
        ('discere:species:77', 'discere:species:78'), ('discere:species:78', 'discere:species:1');"
    create_identity_build_db "$TEST_TMP/build.db"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 1
    assert_contains "$ERR" "Aliase: 1 zeigen auf einen anderen Alias, z. B. discere:species:77 → discere:species:78"
}

# Nach dem Zusammenführen steht in keiner Spalte, die auf eine Entität
# verweist, eine ID mit Quelle; Beiträge ohne Entität sind entfernt, leere
# Verweise NULL, und jeder Fremdschlüssel löst auf.
test_identity_leaves_no_provisional_id() {
    create_release_without_register "$TEST_TMP/prev.db"
    create_identity_build_db "$TEST_TMP/build.db"
    sqlite3 "$TEST_TMP/build.db" "
        INSERT INTO genera (id, external_id, external_source, name, family) VALUES
            ('discere:sealifebase_genus:8', '8', 'sealifebase', 'Amphiprion', 'discere:sealifebase_family:3');
        INSERT INTO species (id, external_id, external_source, name, genus) VALUES
            ('discere:sealifebase_species:7', '7', 'sealifebase', 'ocellaris', 'discere:sealifebase_genus:8');
        INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
            ('discere:sealifebase_species:7', 'Amphiprion ocellaris', 'amphiprion ocellaris', 'valid', 'sealifebase', 1);"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/prev.db"
    assert_status 0
    assert_eq "0" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT COUNT(*) FROM (
            SELECT id AS ref FROM species UNION ALL SELECT genus FROM species
            UNION ALL SELECT id FROM genera UNION ALL SELECT family FROM genera
            UNION ALL SELECT id FROM families UNION ALL SELECT \"order\" FROM families
            UNION ALL SELECT id FROM orders UNION ALL SELECT class FROM orders
            UNION ALL SELECT id FROM classes
            UNION ALL SELECT species FROM pictures
            UNION ALL SELECT species_id FROM species_scientific_names
            UNION ALL SELECT entity_id FROM common_names
            UNION ALL SELECT entity_id FROM taxonomy_traits
            UNION ALL SELECT entity_id FROM taxonomy_distribution_regions
            UNION ALL SELECT entity_id FROM entity_external_ids
            UNION ALL SELECT entity_id FROM entity_source_keys
            UNION ALL SELECT entity_id FROM entity_aliases
        ) WHERE ref GLOB 'discere:*_*:*';")" "IDs mit Quelle"
    assert_eq "0|1|genus:amphiprion" "$(sqlite3 "$TEST_TMP/build.db" "
        SELECT (SELECT COUNT(*) FROM taxonomy_distribution_regions WHERE entity_id NOT IN (SELECT id FROM species)),
               (SELECT COUNT(*) FROM species WHERE genus IS NULL),
               (SELECT entity_id FROM entity_external_ids WHERE entity_type = 'genera');")" \
        "Waisen, leere Verweise, Namensschlüssel"
    assert_eq "" "$(sqlite3 "$TEST_TMP/build.db" "PRAGMA foreign_key_check;")" "Fremdschlüssel"
    assert_contains "$ERR" "Beiträge ohne Entität entfernt: taxonomy_distribution_regions: 1"
}

test_identity_without_predecessor_fails() {
    create_identity_build_db "$TEST_TMP/build.db"
    run_identity "$TEST_TMP/build.db"
    assert_status 1
    assert_contains "$ERR" "Kein Vorgänger: --previous-release <db> oder ausdrücklich --initial."
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/missing.db"
    assert_status 1
    assert_contains "$ERR" "Vorgänger nicht gefunden: $TEST_TMP/missing.db"
    run_identity "$TEST_TMP/build.db" --previous-release "$TEST_TMP/build.db" --initial
    assert_status 1
    assert_contains "$ERR" "--initial und --previous-release schließen sich aus."
}

test_identity_source_with_entities_but_without_priority_fails() {
    create_identity_build_db "$TEST_TMP/build.db"
    make_plugin "$TEST_TMP/plugins" sealifebase
    run_identity "$TEST_TMP/build.db" --initial
    assert_status 1
    assert_contains "$ERR" "Quelle 'sealifebase' liefert Entitäten, hat aber keine placement_priority"
}

# Am Ende des Builds prüft check_references.sh auch die Beiträge der
# ergänzenden Quellen, die nach der Identitäts-Stage geschrieben werden.
test_check_references_rejects_provisional_and_dangling_ids() {
    create_initial_release "$TEST_TMP/build.db"
    run_capture "$ETL_DIR/core/check_references.sh" --db "$TEST_TMP/build.db"
    assert_status 0
    sqlite3 "$TEST_TMP/build.db" "
        INSERT INTO common_names (entity_id, entity_type, language, name, source) VALUES
            ('discere:fishbase_class:7', 'class', 'de', 'Echte Knochenfische', 'curated'),
            ('discere:class:9',          'class', 'fr', 'Téléostéens',         'curated');"
    run_capture "$ETL_DIR/core/check_references.sh" --db "$TEST_TMP/build.db"
    assert_status 1
    assert_contains "$OUT" "common_names.entity_id: 1 vorläufige IDs, z. B. discere:fishbase_class:7"
    assert_contains "$OUT" "common_names.entity_id: 2 IDs ohne Entität"
}
