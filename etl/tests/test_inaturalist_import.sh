#!/usr/bin/env bash
# Tests für plugins/inaturalist/import.sh gegen die Mini-DB aus lib.sh und
# eine kleine taxa.csv.gz (ohne Download)

# Jede taxa.csv.gz enthält Reiche und Stämme, über deren IDs die Taxa der
# Fälle ihre Ahnenkette angeben:
#   Animalia 1 › Chordata 2, Arthropoda 3, Mollusca 4, Entoprocta 5,
#                Acanthocephala 6
#   Plantae 10 › Tracheophyta 11
#   Chromista 20 › Ciliophora 21
CHORDATA='1/2'
ARTHROPODA='1/3'
MOLLUSCA='1/4'
ENTOPROCTA='1/5'
ACANTHOCEPHALA='1/6'
TRACHEOPHYTA='10/11'
CILIOPHORA='20/21'

write_taxa_file() {
    {
        printf 'taxon_id\tancestry\trank_level\trank\tname\tactive\n'
        printf '%s\n' \
            $'1\t\t70\tkingdom\tAnimalia\ttrue' \
            $'2\t1\t60\tphylum\tChordata\ttrue' \
            $'3\t1\t60\tphylum\tArthropoda\ttrue' \
            $'4\t1\t60\tphylum\tMollusca\ttrue' \
            $'5\t1\t60\tphylum\tEntoprocta\ttrue' \
            $'6\t1\t60\tphylum\tAcanthocephala\ttrue' \
            $'10\t\t70\tkingdom\tPlantae\ttrue' \
            $'11\t10\t60\tphylum\tTracheophyta\ttrue' \
            $'20\t\t70\tkingdom\tChromista\ttrue' \
            $'21\t20\t60\tphylum\tCiliophora\ttrue'
        printf '%s\n' "$@"
    } | gzip > "$TEST_TMP/taxa.csv.gz"
}

# Ergänzt die Mini-DB um SeaLifeBase-Ketten für die Stammprüfung:
#   Mollusca › Gastropoda › Littorinimorpha › Triphoridae › Triphora
#     sealifebase_species:1  Triphora pusilla
#     sealifebase_species:2  Ebalia ambiguus  Synonym Paratenuisentis ambiguus
#                            (Gattung Triphora, nur für die Kette)
#   Kamptozoa › Entoprocta › Loxosomatida › Loxosomatidae › Loxosomella
#     sealifebase_species:3  Loxosomella vivipara
#   Arthropoda › Branchiopoda › Notostraca › Triopsidae › Apus
#     (dazu die FishBase-Gattung Apus unter Pomacentridae, Chordata)
#   Not Assigned (Plantae) › Not assigned › Not assigned › Not assigned
#   › Tintinnopsis
#     sealifebase_species:4  Tintinnopsis baltica
#   ohne Gattung
#     sealifebase_species:5  Alsidium pusillum
add_sealifebase_chains() {
    sqlite3 "$DB" << 'SQL'
INSERT INTO classes (id, external_id, external_source, name, super_class) VALUES
    ('discere:sealifebase_class:1', '1', 'sealifebase', 'Gastropoda',   'Mollusca'),
    ('discere:sealifebase_class:2', '2', 'sealifebase', 'Entoprocta',   'Kamptozoa'),
    ('discere:sealifebase_class:3', '3', 'sealifebase', 'Branchiopoda', 'Arthropoda'),
    ('discere:sealifebase_class:4', '4', 'sealifebase', 'Not assigned', 'Not Assigned (Plantae)');
INSERT INTO orders (id, external_id, external_source, name, class) VALUES
    ('discere:sealifebase_order:1', '1', 'sealifebase', 'Littorinimorpha', 'discere:sealifebase_class:1'),
    ('discere:sealifebase_order:2', '2', 'sealifebase', 'Loxosomatida',    'discere:sealifebase_class:2'),
    ('discere:sealifebase_order:3', '3', 'sealifebase', 'Notostraca',      'discere:sealifebase_class:3'),
    ('discere:sealifebase_order:4', '4', 'sealifebase', 'Not assigned',    'discere:sealifebase_class:4');
INSERT INTO families (id, external_id, external_source, name, "order") VALUES
    ('discere:sealifebase_family:1', '1', 'sealifebase', 'Triphoridae',   'discere:sealifebase_order:1'),
    ('discere:sealifebase_family:2', '2', 'sealifebase', 'Loxosomatidae', 'discere:sealifebase_order:2'),
    ('discere:sealifebase_family:3', '3', 'sealifebase', 'Triopsidae',    'discere:sealifebase_order:3'),
    ('discere:sealifebase_family:4', '4', 'sealifebase', 'Not assigned',  'discere:sealifebase_order:4');
INSERT INTO genera (id, external_id, external_source, name, family) VALUES
    ('discere:sealifebase_genus:1', '1', 'sealifebase', 'Triphora',     'discere:sealifebase_family:1'),
    ('discere:sealifebase_genus:2', '2', 'sealifebase', 'Loxosomella',  'discere:sealifebase_family:2'),
    ('discere:sealifebase_genus:3', '3', 'sealifebase', 'Apus',         'discere:sealifebase_family:3'),
    ('discere:sealifebase_genus:4', '4', 'sealifebase', 'Tintinnopsis', 'discere:sealifebase_family:4'),
    ('discere:fishbase_genus:9',    '9', 'fishbase',    'Apus',         'discere:fishbase_family:1');
INSERT INTO species (id, external_id, external_source, name, genus, status) VALUES
    ('discere:sealifebase_species:1', '1', 'sealifebase', 'pusilla',  'discere:sealifebase_genus:1', 'active'),
    ('discere:sealifebase_species:2', '2', 'sealifebase', 'ambiguus', 'discere:sealifebase_genus:1', 'active'),
    ('discere:sealifebase_species:3', '3', 'sealifebase', 'vivipara', 'discere:sealifebase_genus:2', 'active'),
    ('discere:sealifebase_species:4', '4', 'sealifebase', 'baltica',  'discere:sealifebase_genus:4', 'active'),
    ('discere:sealifebase_species:5', '5', 'sealifebase', 'pusillum', NULL,                          'active');
INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
    ('discere:sealifebase_species:1', 'Triphora pusilla',         'triphora pusilla',         'valid',   'sealifebase', 1),
    ('discere:sealifebase_species:2', 'Ebalia ambiguus',          'ebalia ambiguus',          'valid',   'sealifebase', 1),
    ('discere:sealifebase_species:2', 'Paratenuisentis ambiguus', 'paratenuisentis ambiguus', 'synonym', 'sealifebase', 0),
    ('discere:sealifebase_species:3', 'Loxosomella vivipara',     'loxosomella vivipara',     'valid',   'sealifebase', 1),
    ('discere:sealifebase_species:4', 'Tintinnopsis baltica',     'tintinnopsis baltica',     'valid',   'sealifebase', 1),
    ('discere:sealifebase_species:5', 'Alsidium pusillum',        'alsidium pusillum',        'valid',   'sealifebase', 1);
SQL
}

inaturalist_report() {
    tail -n +2 "$TEST_TMP/report/inaturalist.tsv" 2> /dev/null | LC_ALL=C sort || true
}

run_inaturalist_import() {
    export DISCERE_REPORT_DIR="$TEST_TMP/report"
    run_capture "$ETL_DIR/plugins/inaturalist/import.sh" --db "$DB" \
        --taxa-file "$TEST_TMP/taxa.csv.gz" --version v25.04
}

inaturalist_mappings() {
    sqlite3 -separator ' ' "$DB" "SELECT entity_id, entity_type, external_id FROM entity_external_ids
                                  WHERE provider = 'inaturalist' ORDER BY entity_id;"
}

test_inaturalist_maps_unambiguous_taxa_and_reports_the_rest() {
    create_mini_reference_db
    write_taxa_file \
        $'100\t1/2\t10\tspecies\tAmphiprion ocellaris\ttrue' \
        $'101\t1/2\t10\tspecies\tAmphiprion bicolor\ttrue' \
        $'102\t1/2\t10\tspecies\tAmphiprion percula\ttrue' \
        $'103\t1/2\t10\tspecies\tAmphiprion communis\ttrue' \
        $'104\t1/2\t20\tgenus\tAmphiprion\ttrue' \
        $'105\t1/2\t20\tgenus\tAmphiprion\ttrue' \
        $'106\t1/2\t30\tfamily\tPomacentridae\ttrue' \
        $'107\t1/2\t50\tclass\tTeleostei\ttrue' \
        $'108\t1/2\t10\tspecies\tAmphiprion clarkii\tfalse' \
        $'109\t1/2\t10\tspecies\tHomo sapiens\ttrue' \
        $'110\t1/2\t40\torder\tOvalentaria\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "" "$OUT" "stdout"
    assert_contains "$ERR" "[WARN] [inaturalist] Unbekanntes Argument: --version"
    assert_eq "class:teleostei classes 107
discere:fishbase_species:1 species 100
discere:fishbase_species:2 species 102
family:pomacentridae families 106
order:ovalentaria orders 110" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	ambiguous	101	Amphiprion bicolor	weitere Datensätze treffen discere:fishbase_species:1: 100
inaturalist	ambiguous	103	Amphiprion communis	mehrere Entitäten: discere:fishbase_species:2, discere:fishbase_species:3
inaturalist	ambiguous	104, 105	Amphiprion	mehrere aktive iNaturalist-Taxa mit passendem Stamm auf Rang genus" \
        "$(tail -n +2 "$TEST_TMP/report/inaturalist.tsv" | LC_ALL=C sort)" "Build-Bericht"
    assert_eq "inaturalist|CC BY / CC0|https://www.inaturalist.org/taxa/{external_id}" \
        "$(sqlite3 "$DB" "SELECT id, license_key, species_url_template FROM sources WHERE id = 'inaturalist';")" \
        "sources-Eintrag"
}

test_inaturalist_reimport_replaces_its_mappings() {
    create_mini_reference_db
    write_taxa_file $'100\t1/2\t10\tspecies\tAmphiprion ocellaris\ttrue'
    run_inaturalist_import
    assert_status 0
    write_taxa_file $'102\t1/2\t10\tspecies\tAmphiprion percula\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:fishbase_species:2 species 102" "$(inaturalist_mappings)" "Zuordnungen nach Reimport"
}

test_inaturalist_without_taxa_file_fails() {
    create_mini_reference_db
    run_capture "$ETL_DIR/plugins/inaturalist/import.sh" --db "$DB" --taxa-file "$TEST_TMP/missing.csv.gz"
    assert_status 1
    assert_contains "$ERR" "taxa.csv.gz nicht gefunden"
}

test_inaturalist_maps_higher_taxon_name_shared_by_several_rows() {
    create_mini_reference_db
    sqlite3 "$DB" "INSERT INTO genera (id, external_id, external_source, name, family) VALUES
        ('discere:fishbase_genus:2', '2', 'fishbase', 'Premnas', 'discere:fishbase_family:1'),
        ('discere:fishbase_genus:3', '3', 'fishbase', 'Premnas', 'discere:fishbase_family:1');"
    write_taxa_file $'200\t1/2\t20\tgenus\tPremnas\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "genus:premnas genera 200" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	ambiguous	200	Premnas	mehrere Entitäten: discere:fishbase_genus:2, discere:fishbase_genus:3" \
        "$(tail -n +2 "$TEST_TMP/report/inaturalist.tsv")" "Build-Bericht"
}

# Übernommene, deprecated Arten sind keine Kandidaten; ihre Namen grenzen die
# iNaturalist-Taxa deshalb auch nicht ein und landen nicht als none im Bericht.
test_inaturalist_ignores_names_of_deprecated_species() {
    create_mini_reference_db
    write_taxa_file $'100\t1/2\t10\tspecies\tAmphiprion ocellaris\ttrue' \
                    $'300\t1/2\t10\tspecies\tAmphiprion vetus\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:fishbase_species:1 species 100" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "" "$(tail -n +2 "$TEST_TMP/report/inaturalist.tsv" 2> /dev/null || true)" "Build-Bericht"
}

# Stammprüfung (plugins/inaturalist/sql/export.sql): Ein Name allein trennt
# keine Homonyme über Stämme hinweg. Fälle, die ablehnen, ordnen zusätzlich
# Amphiprion ocellaris zu: Ohne jede Zuordnung bricht das Plugin ab.
test_inaturalist_maps_species_whose_phylum_fits_its_chain() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file $'400\t1/4\t10\tspecies\tTriphora pusilla\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:sealifebase_species:1 species 400" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "" "$(inaturalist_report)" "Build-Bericht"
}

test_inaturalist_rejects_species_from_another_phylum() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file $'401\t10/11\t10\tspecies\tTriphora pusilla\ttrue' \
                    $'100\t1/2\t10\tspecies\tAmphiprion ocellaris\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:fishbase_species:1 species 100" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_mismatch	401	Triphora pusilla	iNaturalist: Tracheophyta (Plantae); Kette: discere:sealifebase_species:1 Mollusca" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Kamptozoa in der Kette, Entoprocta bei iNaturalist: gleichwertig laut
# data/phylum_equivalents.csv.
test_inaturalist_maps_species_of_an_equivalent_phylum() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file $'402\t1/5\t10\tspecies\tLoxosomella vivipara\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:sealifebase_species:3 species 402" "$(inaturalist_mappings)" "Zuordnungen"
}

test_inaturalist_rejects_species_without_chain() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file $'403\t10/11\t10\tspecies\tAlsidium pusillum\ttrue' \
                    $'100\t1/2\t10\tspecies\tAmphiprion ocellaris\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:fishbase_species:1 species 100" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_unknown	403	Alsidium pusillum	iNaturalist: Tracheophyta (Plantae); Kette: discere:sealifebase_species:5 ohne Stamm" \
        "$(inaturalist_report)" "Build-Bericht"
}

test_inaturalist_rejects_taxon_without_phylum_in_its_ancestry() {
    create_mini_reference_db
    write_taxa_file $'404\t1\t10\tspecies\tAmphiprion percula\ttrue' \
                    $'100\t1/2\t10\tspecies\tAmphiprion ocellaris\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:fishbase_species:1 species 100" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_unknown	404	Amphiprion percula	iNaturalist: ohne Stamm (Animalia); Kette: discere:fishbase_species:2 Chordata" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Die Krabbe führt den Namen eines Kratzwurms als Synonym.
test_inaturalist_rejects_synonym_from_another_phylum() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file $'405\t1/6\t10\tspecies\tParatenuisentis ambiguus\ttrue' \
                    $'100\t1/2\t10\tspecies\tAmphiprion ocellaris\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:fishbase_species:1 species 100" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_mismatch	405	Paratenuisentis ambiguus	iNaturalist: Acanthocephala (Animalia); Kette: discere:sealifebase_species:2 Mollusca" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Apus ist bei FishBase (Chordata) und SeaLifeBase (Arthropoda) eine Gattung;
# genus:apus stünde für beide.
test_inaturalist_gives_no_key_to_genus_name_across_phyla() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file $'406\t1/2\t20\tgenus\tApus\ttrue' \
                    $'100\t1/2\t10\tspecies\tAmphiprion ocellaris\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:fishbase_species:1 species 100" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_mixed	406	Apus	iNaturalist: Chordata (Animalia); Kette: discere:fishbase_genus:9 Chordata, discere:sealifebase_genus:3 Arthropoda" \
        "$(inaturalist_report)" "Build-Bericht"
}

test_inaturalist_resolves_homonym_with_one_candidate_in_the_phylum() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file $'407\t1/4\t20\tgenus\tTriphora\ttrue' \
                    $'408\t10/11\t20\tgenus\tTriphora\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "genus:triphora genera 407" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_mismatch	408	Triphora	iNaturalist: Tracheophyta (Plantae); Kette: discere:sealifebase_genus:1 Mollusca" \
        "$(inaturalist_report)" "Build-Bericht"
}

# FishBase führt Gobio mehrfach, eine Zeile ohne Familie: Für sie ist der
# Stamm nicht prüfbar, und genus:gobio stünde auch für sie.
test_inaturalist_gives_no_key_to_name_with_a_row_without_chain() {
    create_mini_reference_db
    sqlite3 "$DB" "INSERT INTO genera (id, external_id, external_source, name, family) VALUES
        ('discere:fishbase_genus:2', '2', 'fishbase', 'Premnas', 'discere:fishbase_family:1'),
        ('discere:fishbase_genus:3', '3', 'fishbase', 'Premnas', NULL);"
    write_taxa_file $'200\t1/2\t20\tgenus\tPremnas\ttrue' \
                    $'100\t1/2\t10\tspecies\tAmphiprion ocellaris\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:fishbase_species:1 species 100" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_unknown	200	Premnas	iNaturalist: Chordata (Animalia); Kette: discere:fishbase_genus:2 Chordata, discere:fishbase_genus:3 ohne Stamm" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Ein Platzhalter-Stamm, der ein Reich nennt, prüft wenigstens das Reich.
test_inaturalist_checks_kingdom_for_placeholder_phylum() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file $'409\t20/21\t10\tspecies\tTintinnopsis baltica\ttrue' \
                    $'410\t10/11\t20\tgenus\tTintinnopsis\ttrue'
    run_inaturalist_import
    assert_status 0
    assert_eq "genus:tintinnopsis genera 410" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_mismatch	409	Tintinnopsis baltica	iNaturalist: Ciliophora (Chromista); Kette: discere:sealifebase_species:4 Not Assigned (Plantae)" \
        "$(inaturalist_report)" "Build-Bericht"
}
