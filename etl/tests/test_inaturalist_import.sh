#!/usr/bin/env bash
# Tests für plugins/inaturalist/import.sh gegen die Mini-DB aus lib.sh und
# eine kleine taxa.csv.gz (ohne Download)

# Jede taxa.csv.gz enthält diese höheren Taxa; die Taxa der Fälle geben ihre
# Ahnenkette über deren IDs an:
#   Animalia 1
#     Chordata 2     › Actinopterygii 30 › Ovalentaria 31 › Pomacentridae 32
#                    › Aves 33 › Apodiformes 34 › Apodidae 35
#                    › Reptilia 36
#     Arthropoda 3   › Insecta 50
#     Mollusca 4     › Gastropoda 40 › Littorinimorpha 41 › Triphoridae 42
#                                    › Neogastropoda 43 › Conidae 44
#                    › Bivalvia 45
#     Entoprocta 5, Acanthocephala 6
#   Plantae 10 › Tracheophyta 11
#   Chromista 20 › Ciliophora 21
CHORDATA='1/2'
ACTINOPTERYGII='1/2/30'
OVALENTARIA='1/2/30/31'
POMACENTRIDAE='1/2/30/31/32'
APODIDAE='1/2/33/34/35'
REPTILIA='1/2/36'
INSECTA='1/3/50'
TRIPHORIDAE='1/4/40/41/42'
CONIDAE='1/4/40/43/44'
BIVALVIA='1/4/45'
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
            $'21\t20\t60\tphylum\tCiliophora\ttrue' \
            $'30\t1/2\t50\tclass\tActinopterygii\ttrue' \
            $'31\t1/2/30\t40\torder\tOvalentaria\ttrue' \
            $'32\t1/2/30/31\t30\tfamily\tPomacentridae\ttrue' \
            $'33\t1/2\t50\tclass\tAves\ttrue' \
            $'34\t1/2/33\t40\torder\tApodiformes\ttrue' \
            $'35\t1/2/33/34\t30\tfamily\tApodidae\ttrue' \
            $'36\t1/2\t50\tclass\tReptilia\ttrue' \
            $'40\t1/4\t50\tclass\tGastropoda\ttrue' \
            $'41\t1/4/40\t40\torder\tLittorinimorpha\ttrue' \
            $'42\t1/4/40/41\t30\tfamily\tTriphoridae\ttrue' \
            $'43\t1/4/40\t40\torder\tNeogastropoda\ttrue' \
            $'44\t1/4/40/43\t30\tfamily\tConidae\ttrue' \
            $'45\t1/4\t50\tclass\tBivalvia\ttrue' \
            $'50\t1/3\t50\tclass\tInsecta\ttrue'
        printf '%s\n' "$@"
    } | gzip > "$TEST_TMP/taxa.csv.gz"
}

# Ergänzt die Mini-DB um SeaLifeBase-Ketten:
#   Mollusca › Gastropoda › Littorinimorpha › Triphoridae › Triphora
#     sealifebase_species:1  Triphora pusilla
#     sealifebase_species:2  Ebalia ambiguus  Synonym Paratenuisentis ambiguus
#                            (Gattung Triphora, nur für die Kette)
#   Kamptozoa › Entoprocta › Loxosomatida › Loxosomatidae › Loxosomella
#     sealifebase_species:3  Loxosomella vivipara
#   Arthropoda › Branchiopoda › Notostraca › Triopsidae › Apus
#     (dazu die FishBase-Gattung Apus unter Pomacentridae, Chordata)
#   Chordata › Aves › Apodiformes › Apodidae › Batis
#     (dazu die FishBase-Gattung Batis unter Pomacentridae, Teleostei)
#   An jeder Gattung Apus und Batis hängt eine Art, bei FishBase eine
#   veraltete: Auch sie macht die Zeile zum Träger des Schlüssels.
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
    ('discere:sealifebase_class:4', '4', 'sealifebase', 'Not assigned', 'Not Assigned (Plantae)'),
    ('discere:sealifebase_class:5', '5', 'sealifebase', 'Aves',         'Chordata');
INSERT INTO orders (id, external_id, external_source, name, class) VALUES
    ('discere:sealifebase_order:1', '1', 'sealifebase', 'Littorinimorpha', 'discere:sealifebase_class:1'),
    ('discere:sealifebase_order:2', '2', 'sealifebase', 'Loxosomatida',    'discere:sealifebase_class:2'),
    ('discere:sealifebase_order:3', '3', 'sealifebase', 'Notostraca',      'discere:sealifebase_class:3'),
    ('discere:sealifebase_order:4', '4', 'sealifebase', 'Not assigned',    'discere:sealifebase_class:4'),
    ('discere:sealifebase_order:5', '5', 'sealifebase', 'Apodiformes',     'discere:sealifebase_class:5');
INSERT INTO families (id, external_id, external_source, name, "order") VALUES
    ('discere:sealifebase_family:1', '1', 'sealifebase', 'Triphoridae',   'discere:sealifebase_order:1'),
    ('discere:sealifebase_family:2', '2', 'sealifebase', 'Loxosomatidae', 'discere:sealifebase_order:2'),
    ('discere:sealifebase_family:3', '3', 'sealifebase', 'Triopsidae',    'discere:sealifebase_order:3'),
    ('discere:sealifebase_family:4', '4', 'sealifebase', 'Not assigned',  'discere:sealifebase_order:4'),
    ('discere:sealifebase_family:5', '5', 'sealifebase', 'Apodidae',      'discere:sealifebase_order:5');
INSERT INTO genera (id, external_id, external_source, name, family) VALUES
    ('discere:sealifebase_genus:1', '1', 'sealifebase', 'Triphora',     'discere:sealifebase_family:1'),
    ('discere:sealifebase_genus:2', '2', 'sealifebase', 'Loxosomella',  'discere:sealifebase_family:2'),
    ('discere:sealifebase_genus:3', '3', 'sealifebase', 'Apus',         'discere:sealifebase_family:3'),
    ('discere:sealifebase_genus:4', '4', 'sealifebase', 'Tintinnopsis', 'discere:sealifebase_family:4'),
    ('discere:sealifebase_genus:5', '5', 'sealifebase', 'Batis',        'discere:sealifebase_family:5'),
    ('discere:fishbase_genus:9',    '9', 'fishbase',    'Apus',         'discere:fishbase_family:1'),
    ('discere:fishbase_genus:10',  '10', 'fishbase',    'Batis',        'discere:fishbase_family:1');
INSERT INTO species (id, external_id, external_source, name, genus, status) VALUES
    ('discere:sealifebase_species:1', '1', 'sealifebase', 'pusilla',  'discere:sealifebase_genus:1', 'active'),
    ('discere:sealifebase_species:2', '2', 'sealifebase', 'ambiguus', 'discere:sealifebase_genus:1', 'active'),
    ('discere:sealifebase_species:3', '3', 'sealifebase', 'vivipara', 'discere:sealifebase_genus:2', 'active'),
    ('discere:sealifebase_species:4', '4', 'sealifebase', 'baltica',  'discere:sealifebase_genus:4', 'active'),
    ('discere:sealifebase_species:5', '5', 'sealifebase', 'pusillum', NULL,                          'active'),
    ('discere:sealifebase_species:6', '6', 'sealifebase', 'cancriformis', 'discere:sealifebase_genus:3', 'active'),
    ('discere:sealifebase_species:7', '7', 'sealifebase', 'dimidiata',    'discere:sealifebase_genus:5', 'active'),
    ('discere:fishbase_species:9',    '9', 'fishbase',    'apus',         'discere:fishbase_genus:9',    'deprecated'),
    ('discere:fishbase_species:10',  '10', 'fishbase',    'batis',        'discere:fishbase_genus:10',   'deprecated');
INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
    ('discere:sealifebase_species:1', 'Triphora pusilla',         'triphora pusilla',         'valid',   'sealifebase', 1),
    ('discere:sealifebase_species:2', 'Ebalia ambiguus',          'ebalia ambiguus',          'valid',   'sealifebase', 1),
    ('discere:sealifebase_species:2', 'Paratenuisentis ambiguus', 'paratenuisentis ambiguus', 'synonym', 'sealifebase', 0),
    ('discere:sealifebase_species:3', 'Loxosomella vivipara',     'loxosomella vivipara',     'valid',   'sealifebase', 1),
    ('discere:sealifebase_species:4', 'Tintinnopsis baltica',     'tintinnopsis baltica',     'valid',   'sealifebase', 1),
    ('discere:sealifebase_species:5', 'Alsidium pusillum',        'alsidium pusillum',        'valid',   'sealifebase', 1);
SQL
}

# Hängt an jede genannte Gattung eine Art: Als Träger eines
# Namensschlüssels zählt nur eine Gattung mit Art.
give_species_to() {
    local genus
    for genus in "$@"; do
        sqlite3 "$DB" "INSERT INTO species (id, external_id, external_source, name, genus, status)
                       VALUES ('$genus:species', '$genus', 'test', 's', '$genus', 'active');"
    done
}

# Fälle, die ablehnen, ordnen zusätzlich Amphiprion ocellaris zu: Ohne jede
# Zuordnung bricht das Plugin ab.
OCELLARIS="100	$POMACENTRIDAE	10	species	Amphiprion ocellaris	true"
OCELLARIS_MAPPING="discere:fishbase_species:1 species 100"

run_inaturalist_import() {
    export DISCERE_REPORT_DIR="$TEST_TMP/report"
    run_capture "$ETL_DIR/plugins/inaturalist/import.sh" --db "$DB" \
        --taxa-file "$TEST_TMP/taxa.csv.gz" --version v25.04
}

# Zuordnungen und Bericht der Taxa eines Falls (IDs ab 100); die höheren
# Taxa aus write_taxa_file treffen gleichnamige der Mini-DB mit.
inaturalist_mappings() {
    sqlite3 -separator ' ' "$DB" "SELECT entity_id, entity_type, external_id FROM entity_external_ids
                                  WHERE provider = 'inaturalist' AND CAST(external_id AS INTEGER) >= 100
                                  ORDER BY entity_id;"
}

inaturalist_report() {
    tail -n +2 "$TEST_TMP/report/inaturalist.tsv" 2> /dev/null \
        | awk -F '\t' '$3 + 0 >= 100' | LC_ALL=C sort || true
}

test_inaturalist_maps_unambiguous_taxa_and_reports_the_rest() {
    create_mini_reference_db
    write_taxa_file \
        "$OCELLARIS" \
        "101	$POMACENTRIDAE	10	species	Amphiprion bicolor	true" \
        "102	$POMACENTRIDAE	10	species	Amphiprion percula	true" \
        "103	$POMACENTRIDAE	10	species	Amphiprion communis	true" \
        "104	$POMACENTRIDAE	20	genus	Amphiprion	true" \
        "105	$POMACENTRIDAE	20	genus	Amphiprion	true" \
        "107	$CHORDATA	50	class	Teleostei	true" \
        "108	$POMACENTRIDAE	10	species	Amphiprion clarkii	false" \
        "109	$CHORDATA	10	species	Homo sapiens	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "" "$OUT" "stdout"
    assert_contains "$ERR" "[WARN] [inaturalist] Unbekanntes Argument: --version"
    assert_eq "class:teleostei classes 107
discere:fishbase_species:1 species 100
discere:fishbase_species:2 species 102" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "family:pomacentridae 32
order:ovalentaria 31" "$(sqlite3 -separator ' ' "$DB" "SELECT entity_id, external_id FROM entity_external_ids
                                                    WHERE entity_type IN ('families', 'orders') ORDER BY 1;")" \
        "Familie und Ordnung aus der Ahnenkette"
    assert_eq "inaturalist	ambiguous	101	Amphiprion bicolor	weitere Datensätze treffen discere:fishbase_species:1: 100
inaturalist	ambiguous	103	Amphiprion communis	mehrere Entitäten: discere:fishbase_species:2, discere:fishbase_species:3
inaturalist	ambiguous	104, 105	Amphiprion	mehrere aktive iNaturalist-Taxa passend zur Kette auf Rang genus" \
        "$(inaturalist_report)" "Build-Bericht"
    assert_eq "inaturalist|CC BY / CC0|https://www.inaturalist.org/taxa/{external_id}" \
        "$(sqlite3 "$DB" "SELECT id, license_key, species_url_template FROM sources WHERE id = 'inaturalist';")" \
        "sources-Eintrag"
}

# metadata_json hält fest, wogegen geprüft wurde; validate() prüft damit
# jede Zuordnung erneut.
test_inaturalist_records_checked_lineage_in_metadata() {
    create_mini_reference_db
    write_taxa_file "$OCELLARIS"
    run_inaturalist_import
    assert_status 0
    assert_eq 'discere:fishbase_species:1 {"phylum":"Chordata","class":"Actinopterygii","order":"Ovalentaria","family":"Pomacentridae","matched_by":"name","homonym":0}
family:pomacentridae {"phylum":"Chordata","class":"Actinopterygii","order":"Ovalentaria","family":null,"matched_by":"name","homonym":0}' \
        "$(sqlite3 -separator ' ' "$DB" "SELECT entity_id, metadata_json FROM entity_external_ids
                                         WHERE entity_id IN ('discere:fishbase_species:1', 'family:pomacentridae')
                                         ORDER BY entity_id;")" "metadata_json"
}

test_inaturalist_reimport_replaces_its_mappings() {
    create_mini_reference_db
    write_taxa_file "$OCELLARIS"
    run_inaturalist_import
    assert_status 0
    write_taxa_file "102	$POMACENTRIDAE	10	species	Amphiprion percula	true"
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
    give_species_to discere:fishbase_genus:2 discere:fishbase_genus:3
    write_taxa_file "200	$POMACENTRIDAE	20	genus	Premnas	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "genus:premnas genera 200" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	ambiguous	200	Premnas	mehrere Entitäten: discere:fishbase_genus:2, discere:fishbase_genus:3" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Übernommene, deprecated Arten sind keine Kandidaten; ihre Namen grenzen die
# iNaturalist-Taxa deshalb auch nicht ein und landen nicht als none im Bericht.
test_inaturalist_ignores_names_of_deprecated_species() {
    create_mini_reference_db
    write_taxa_file "$OCELLARIS" "300	$POMACENTRIDAE	10	species	Amphiprion vetus	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "" "$(inaturalist_report)" "Build-Bericht"
}

# Prüfung gegen die eigene Kette (plugins/inaturalist/sql/export.sql): Ein
# Name allein trennt keine Homonyme.
test_inaturalist_maps_species_whose_phylum_fits_its_chain() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "400	$TRIPHORIDAE	10	species	Triphora pusilla	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:sealifebase_species:1 species 400" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "" "$(inaturalist_report)" "Build-Bericht"
}

test_inaturalist_rejects_species_from_another_phylum() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "$OCELLARIS" "401	$TRACHEOPHYTA	10	species	Triphora pusilla	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_mismatch	401	Triphora pusilla	iNaturalist: Tracheophyta / - / - / -; Kette: discere:sealifebase_species:1 Mollusca / Gastropoda / Littorinimorpha / Triphoridae" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Kamptozoa in der Kette, Entoprocta bei iNaturalist: gleichwertig laut
# data/phylum_equivalents.csv.
test_inaturalist_maps_species_of_an_equivalent_phylum() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "402	$ENTOPROCTA	10	species	Loxosomella vivipara	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:sealifebase_species:3 species 402" "$(inaturalist_mappings)" "Zuordnungen"
}

test_inaturalist_rejects_species_without_chain() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "$OCELLARIS" "403	$TRACHEOPHYTA	10	species	Alsidium pusillum	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_unknown	403	Alsidium pusillum	iNaturalist: Tracheophyta / - / - / -; Kette: discere:sealifebase_species:5 - / - / - / -" \
        "$(inaturalist_report)" "Build-Bericht"
}

test_inaturalist_rejects_taxon_without_phylum_in_its_ancestry() {
    create_mini_reference_db
    write_taxa_file "$OCELLARIS" "404	1	10	species	Amphiprion percula	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_unknown	404	Amphiprion percula	iNaturalist: - / - / - / -; Kette: discere:fishbase_species:2 Chordata / Teleostei / Ovalentaria / Pomacentridae" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Die Krabbe führt den Namen eines Kratzwurms als Synonym.
test_inaturalist_rejects_synonym_from_another_phylum() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "$OCELLARIS" "405	$ACANTHOCEPHALA	10	species	Paratenuisentis ambiguus	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_mismatch	405	Paratenuisentis ambiguus	iNaturalist: Acanthocephala / - / - / -; Kette: discere:sealifebase_species:2 Mollusca / Gastropoda / Littorinimorpha / Triphoridae" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Apus ist bei FishBase (Chordata) und SeaLifeBase (Arthropoda) eine Gattung;
# genus:apus stünde für beide.
test_inaturalist_gives_no_key_to_genus_name_across_phyla() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "$OCELLARIS" "406	$APODIDAE	20	genus	Apus	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_mixed	406	Apus	iNaturalist: Chordata / Aves / Apodiformes / Apodidae; Kette: discere:fishbase_genus:9 Chordata / Teleostei / Ovalentaria / Pomacentridae, discere:sealifebase_genus:3 Arthropoda / Branchiopoda / Notostraca / Triopsidae" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Batis ist bei FishBase ein Fisch, bei SeaLifeBase ein Vogel: derselbe
# Stamm, verschiedene Klassen; genus:batis stünde für beide.
test_inaturalist_gives_no_key_to_genus_name_across_classes() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "$OCELLARIS" "413	$APODIDAE	20	genus	Batis	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	class_mixed	413	Batis	iNaturalist: Chordata / Aves / Apodiformes / Apodidae; Kette: discere:fishbase_genus:10 Chordata / Teleostei / Ovalentaria / Pomacentridae, discere:sealifebase_genus:5 Chordata / Aves / Apodiformes / Apodidae" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Eine gleichnamige Zeile ohne Kette, an der eine Art hängt: Für sie ist der
# Stamm nicht prüfbar, und genus:premnas stünde auch für sie.
test_inaturalist_gives_no_key_to_name_with_a_row_without_chain() {
    create_mini_reference_db
    sqlite3 "$DB" "INSERT INTO genera (id, external_id, external_source, name, family) VALUES
        ('discere:fishbase_genus:2', '2', 'fishbase', 'Premnas', 'discere:fishbase_family:1'),
        ('discere:fishbase_genus:3', '3', 'fishbase', 'Premnas', NULL);"
    give_species_to discere:fishbase_genus:2 discere:fishbase_genus:3
    write_taxa_file "200	$POMACENTRIDAE	20	genus	Premnas	true" "$OCELLARIS"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_unknown	200	Premnas	iNaturalist: Chordata / Actinopterygii / Ovalentaria / Pomacentridae; Kette: discere:fishbase_genus:2 Chordata / Teleostei / Ovalentaria / Pomacentridae, discere:fishbase_genus:3 - / - / - / -" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Eine Zeile ohne jede Art (FishBase und SeaLifeBase führen so etwa
# Synonymgattungen) zeigt die App unter keinem Schlüssel; sie verhindert
# deshalb keine Zuordnung, auch ohne Kette oder in einem anderen Stamm.
# Hängt an ihr eine Art, zählt sie.
test_inaturalist_ignores_name_rows_without_species() {
    create_mini_reference_db
    add_sealifebase_chains
    sqlite3 "$DB" "INSERT INTO genera (id, external_id, external_source, name, family) VALUES
        ('discere:fishbase_genus:2',    '2', 'fishbase',    'Premnas', 'discere:fishbase_family:1'),
        ('discere:fishbase_genus:3',    '3', 'fishbase',    'Premnas', NULL),
        ('discere:sealifebase_genus:9', '9', 'sealifebase', 'Premnas', 'discere:sealifebase_family:1');"
    give_species_to discere:fishbase_genus:2
    write_taxa_file "200	$POMACENTRIDAE	20	genus	Premnas	true" "$OCELLARIS"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING
genus:premnas genera 200" "$(inaturalist_mappings)" "Zuordnungen ohne Art an den übrigen Zeilen"
    give_species_to discere:sealifebase_genus:9
    rm -rf "$TEST_TMP/report"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING" "$(inaturalist_mappings)" "Zuordnungen mit Art an der Schnecken-Zeile"
    assert_eq "inaturalist	phylum_mixed	200	Premnas	iNaturalist: Chordata / Actinopterygii / Ovalentaria / Pomacentridae; Kette: discere:fishbase_genus:2 Chordata / Teleostei / Ovalentaria / Pomacentridae, discere:sealifebase_genus:9 Mollusca / Gastropoda / Littorinimorpha / Triphoridae" \
        "$(inaturalist_report | grep Premnas)" "Build-Bericht"
}

# Eine Gattung braucht über den Stamm hinaus Klasse, Ordnung oder Familie:
# Fisch bei uns, Echse bei iNaturalist, beide Chordata.
test_inaturalist_rejects_higher_taxon_whose_class_order_and_family_differ() {
    create_mini_reference_db
    sqlite3 "$DB" "INSERT INTO genera (id, external_id, external_source, name, family) VALUES
        ('discere:fishbase_genus:2', '2', 'fishbase', 'Premnas', 'discere:fishbase_family:1');"
    give_species_to discere:fishbase_genus:2
    write_taxa_file "$OCELLARIS" "201	$REPTILIA	20	genus	Premnas	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	rank_mismatch	201	Premnas	iNaturalist: Chordata / Reptilia / - / -; Kette: discere:fishbase_genus:2 Chordata / Teleostei / Ovalentaria / Pomacentridae" \
        "$(inaturalist_report)" "Build-Bericht"
}

test_inaturalist_resolves_homonym_with_one_candidate_fitting_the_chain() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "407	$TRIPHORIDAE	20	genus	Triphora	true" \
                    "408	$TRACHEOPHYTA	20	genus	Triphora	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "genus:triphora genera 407" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_mismatch	408	Triphora	iNaturalist: Tracheophyta / - / - / -; Kette: discere:sealifebase_genus:1 Mollusca / Gastropoda / Littorinimorpha / Triphoridae" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Trägt ein Artname bei iNaturalist mehrere Taxa, genügt der Stamm nicht:
# Das übrige Taxon braucht Klasse, Ordnung oder Familie der Art. Ohne das
# Homonym würde dieselbe Muschel über den Stamm allein zugeordnet.
test_inaturalist_rejects_species_homonym_left_only_by_phylum() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "$OCELLARIS" \
                    "411	$BIVALVIA	10	species	Triphora pusilla	true" \
                    "412	$TRACHEOPHYTA	10	species	Triphora pusilla	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_mismatch	412	Triphora pusilla	iNaturalist: Tracheophyta / - / - / -; Kette: discere:sealifebase_species:1 Mollusca / Gastropoda / Littorinimorpha / Triphoridae
inaturalist	rank_mismatch	411	Triphora pusilla	iNaturalist: Mollusca / Bivalvia / - / -; Kette: discere:sealifebase_species:1 Mollusca / Gastropoda / Littorinimorpha / Triphoridae" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Bekannte Grenze: Ein Homonym im selben Stamm und in derselben Klasse
# (eine Kegelschnecke, wo wir eine Triphoride führen) passt über die Klasse
# und wird zugeordnet.
test_inaturalist_cannot_tell_homonym_within_one_class() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "414	$CONIDAE	20	genus	Triphora	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "genus:triphora genera 414" "$(inaturalist_mappings)" "Zuordnungen"
}

# Ein Platzhalter-Stamm ist nicht prüfbar, auch wenn er ein Reich nennt:
# SeaLifeBase ordnet darunter Einzeller falschen Reichen zu (Tintinnopsis
# ist ein Wimpertierchen, kein Plantae-Taxon).
test_inaturalist_rejects_placeholder_phylum_even_with_kingdom() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "$OCELLARIS" \
                    "409	$CILIOPHORA	10	species	Tintinnopsis baltica	true" \
                    "410	$TRACHEOPHYTA	20	genus	Tintinnopsis	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	phylum_unknown	409	Tintinnopsis baltica	iNaturalist: Ciliophora / - / - / -; Kette: discere:sealifebase_species:4 Not Assigned (Plantae) / Not assigned / Not assigned / Not assigned
inaturalist	phylum_unknown	410	Tintinnopsis	iNaturalist: Tracheophyta / - / - / -; Kette: discere:sealifebase_genus:4 Not Assigned (Plantae) / Not assigned / Not assigned / Not assigned" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Über ein Synonym nur bei gleicher Familie: SeaLifeBase führt Synonyme, die
# anderen Arten gehören. Amphiprion frenata (Genusangleichung von frenatus)
# ist dagegen ein Synonym derselben Art.
test_inaturalist_maps_synonym_only_with_the_same_family() {
    create_mini_reference_db
    add_frenata_synonym
    write_taxa_file "501	$POMACENTRIDAE	10	species	Amphiprion frenata	true" \
                    "502	$APODIDAE	10	species	Amphiprion bicolor	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:fishbase_species:5 species 501" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	synonym_family	502	Amphiprion bicolor	iNaturalist-Familie: Apodidae; Familie von discere:fishbase_species:1: Pomacentridae" \
        "$(inaturalist_report)" "Build-Bericht"
    assert_eq '{"phylum":"Chordata","class":"Actinopterygii","order":"Ovalentaria","family":"Pomacentridae","matched_by":"synonym","homonym":0}' \
        "$(sqlite3 "$DB" "SELECT metadata_json FROM entity_external_ids WHERE external_id = '501';")" "metadata_json"
}

# Auch in derselben Familie führt SeaLifeBase Synonyme anderer Arten (Mactra
# mera mit dem Synonym Mactra antiquata): Das Epitheton des Synonyms muss in
# den ersten vier Buchstaben dem der Art gleichen. Amphiprion melanopus ist
# hier Synonym von Amphiprion frenatus.
test_inaturalist_rejects_synonym_with_another_epithet() {
    create_mini_reference_db
    write_taxa_file "$OCELLARIS" "503	$POMACENTRIDAE	10	species	Amphiprion melanopus	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "$OCELLARIS_MAPPING" "$(inaturalist_mappings)" "Zuordnungen"
    assert_eq "inaturalist	synonym_epithet	503	Amphiprion melanopus	Epitheton von discere:fishbase_species:5: frenatus" \
        "$(inaturalist_report)" "Build-Bericht"
}

# Jede Entität, für die der Abgleich ein Taxon ihres Namens bewusst nicht
# nimmt, steht mit Grund in entity_external_id_rejections — außer sie hat
# trotzdem eine Zuordnung: Amphiprion ocellaris und percula über ihren
# akzeptierten Namen, genus:triphora über das passende der zwei Taxa.
test_inaturalist_records_rejected_entities() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file \
        "$OCELLARIS" \
        "102	$POMACENTRIDAE	10	species	Amphiprion percula	true" \
        "103	$POMACENTRIDAE	10	species	Amphiprion communis	true" \
        "104	$POMACENTRIDAE	20	genus	Amphiprion	true" \
        "105	$POMACENTRIDAE	20	genus	Amphiprion	true" \
        "401	$TRACHEOPHYTA	10	species	Triphora pusilla	true" \
        "403	$TRACHEOPHYTA	10	species	Alsidium pusillum	true" \
        "406	$APODIDAE	20	genus	Apus	true" \
        "407	$TRIPHORIDAE	20	genus	Triphora	true" \
        "408	$TRACHEOPHYTA	20	genus	Triphora	true" \
        "413	$APODIDAE	20	genus	Batis	true" \
        "502	$APODIDAE	10	species	Amphiprion bicolor	true" \
        "503	$POMACENTRIDAE	10	species	Amphiprion melanopus	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:fishbase_species:3 species ambiguous
discere:fishbase_species:5 species synonym_epithet
discere:sealifebase_species:1 species phylum_mismatch
discere:sealifebase_species:5 species phylum_unknown
genus:amphiprion genera ambiguous
genus:apus genera phylum_mixed
genus:batis genera class_mixed" \
        "$(sqlite3 -separator ' ' "$DB" "SELECT entity_id, entity_type, reason FROM entity_external_id_rejections
                                         WHERE provider = 'inaturalist' ORDER BY 1, 3;")" "Ablehnungen"
}

test_inaturalist_reimport_replaces_its_rejections() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "$OCELLARIS" "401	$TRACHEOPHYTA	10	species	Triphora pusilla	true"
    run_inaturalist_import
    assert_status 0
    write_taxa_file "400	$TRIPHORIDAE	10	species	Triphora pusilla	true"
    run_inaturalist_import
    assert_status 0
    assert_eq "" "$(sqlite3 "$DB" "SELECT entity_id FROM entity_external_id_rejections;")" "Ablehnungen nach Reimport"
}

# Je Klasse die iNaturalist-IDs von Stamm und Klasse, gegen die die App die
# ancestor_ids eines Suchtreffers prüft: Teleostei (FishBase, also Chordata)
# zu Actinopterygii und Kamptozoa zu Entoprocta über die Listen
# gleichwertiger Namen; Entoprocta und Branchiopoda führt iNaturalist nicht
# als Klasse, der Platzhalter-Stamm bekommt nichts.
test_inaturalist_records_allowed_ancestors_per_class() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "$OCELLARIS"
    run_inaturalist_import
    assert_status 0
    assert_eq "discere:fishbase_class:7 class 30
discere:fishbase_class:7 phylum 2
discere:sealifebase_class:1 class 40
discere:sealifebase_class:1 phylum 4
discere:sealifebase_class:2 phylum 5
discere:sealifebase_class:3 phylum 3
discere:sealifebase_class:5 class 33
discere:sealifebase_class:5 phylum 2" \
        "$(sqlite3 -separator ' ' "$DB" "SELECT class_id, rank, inat_taxon_id FROM inat_allowed_ancestors ORDER BY 1, 2, 3;")" \
        "erlaubte Vorfahren"
}

# Ein Stamm, den iNaturalist nicht führt und zu dem kein gleichwertiger
# eingetragen ist: Die App fände für die Arten der Klasse nie eine ID. Der
# Build bricht ab, damit das Paar in data/phylum_equivalents.csv landet.
# Eine Klasse ohne Art erreicht die App nicht; sie zählt nicht.
add_placozoa_class() {
    sqlite3 "$DB" "INSERT INTO classes (id, external_id, external_source, name, super_class) VALUES
        ('discere:sealifebase_class:9', '9', 'sealifebase', 'Placozoa', 'Placozoa');
    INSERT INTO orders (id, external_id, external_source, name, class) VALUES
        ('discere:sealifebase_order:9', '9', 'sealifebase', 'Trichoplacida', 'discere:sealifebase_class:9');
    INSERT INTO families (id, external_id, external_source, name, \"order\") VALUES
        ('discere:sealifebase_family:9', '9', 'sealifebase', 'Trichoplacidae', 'discere:sealifebase_order:9');
    INSERT INTO genera (id, external_id, external_source, name, family) VALUES
        ('discere:sealifebase_genus:9', '9', 'sealifebase', 'Trichoplax', 'discere:sealifebase_family:9');"
}

test_inaturalist_validation_fails_on_class_without_allowed_phylum() {
    create_mini_reference_db
    add_placozoa_class
    give_species_to discere:sealifebase_genus:9
    write_taxa_file "$OCELLARIS"
    run_inaturalist_import
    assert_status 1
    assert_contains "$ERR" "class:placozoa		erlaubter stamm fehlt	discere:sealifebase_class:9"
}

test_inaturalist_validation_ignores_class_without_species() {
    create_mini_reference_db
    add_placozoa_class
    write_taxa_file "$OCELLARIS"
    run_inaturalist_import
    assert_status 0
}

# validate() prüft jede Zuordnung mit eigener SQL gegen taxa.csv und die
# Kette. Eine Kopie des Plugins, deren Prüfung oder metadata_json kaputt
# ist, muss deshalb scheitern, statt die falsche Zuordnung zu schreiben.
run_broken_plugin() {
    local file="$1" old="$2" new="$3"
    mkdir -p "$TEST_TMP/etl/plugins"
    cp -R "$ETL_DIR/core" "$TEST_TMP/etl/core"
    cp -R "$ETL_DIR/plugins/inaturalist" "$TEST_TMP/etl/plugins/inaturalist"
    OLD="$old" NEW="$new" python3 -c '
import os, sys
path = sys.argv[1]
text = open(path).read()
assert text.count(os.environ["OLD"]) == 1, os.environ["OLD"]
open(path, "w").write(text.replace(os.environ["OLD"], os.environ["NEW"]))' \
        "$TEST_TMP/etl/plugins/inaturalist/$file"
    export DISCERE_REPORT_DIR="$TEST_TMP/report"
    run_capture "$TEST_TMP/etl/plugins/inaturalist/import.sh" --db "$DB" --taxa-file "$TEST_TMP/taxa.csv.gz"
}

test_inaturalist_validation_fails_on_wrong_phylum() {
    create_mini_reference_db
    add_sealifebase_chains
    write_taxa_file "$OCELLARIS" "401	$TRACHEOPHYTA	10	species	Triphora pusilla	true"
    run_broken_plugin sql/export.sql "        ELSE l.phylum = c.chain_phylum" "        ELSE true"
    assert_status 1
    assert_contains "$ERR" "Zuordnungen passen nicht zur Kette (1):"
    assert_contains "$ERR" "discere:sealifebase_species:1	401	stamm	discere:sealifebase_species:1"
}

test_inaturalist_validation_fails_on_wrong_class() {
    create_mini_reference_db
    sqlite3 "$DB" "INSERT INTO genera (id, external_id, external_source, name, family) VALUES
        ('discere:fishbase_genus:2', '2', 'fishbase', 'Premnas', 'discere:fishbase_family:1');"
    give_species_to discere:fishbase_genus:2
    write_taxa_file "$OCELLARIS" "201	$REPTILIA	20	genus	Premnas	true"
    run_broken_plugin sql/export.sql "             AND NOT bool_and(k.rank_fits) THEN 'rank_mismatch'" \
                                     "             AND false THEN 'rank_mismatch'"
    assert_status 1
    assert_contains "$ERR" "genus:premnas	201	rang	discere:fishbase_genus:2"
}

test_inaturalist_validation_fails_on_synonym_of_another_species() {
    create_mini_reference_db
    write_taxa_file "502	$APODIDAE	10	species	Amphiprion bicolor	true" \
                    "503	$POMACENTRIDAE	10	species	Amphiprion melanopus	true"
    run_broken_plugin import.sh "WHERE record_key NOT IN (SELECT record_key FROM tmp_rejected);" "WHERE 1;"
    assert_status 1
    assert_contains "$ERR" "Zuordnungen passen nicht zur Kette (2):"
    assert_contains "$ERR" "discere:fishbase_species:1	502	synonym	discere:fishbase_species:1"
    assert_contains "$ERR" "discere:fishbase_species:5	503	synonym	discere:fishbase_species:5"
}

test_inaturalist_validation_fails_on_wrong_metadata() {
    create_mini_reference_db
    write_taxa_file "$OCELLARIS"
    run_broken_plugin import.sh "json_object('phylum', phylum," "json_object('phylum', 'Mollusca',"
    assert_status 1
    assert_contains "$ERR" "discere:fishbase_species:1	100	metadata"
}

test_inaturalist_validation_fails_on_wrong_allowed_ancestor() {
    create_mini_reference_db
    write_taxa_file "$OCELLARIS"
    run_broken_plugin sql/export.sql "          AND (t.name = c.chain_phylum" "          AND (true"
    assert_status 1
    assert_contains "$ERR" "class:teleostei	3	erlaubter vorfahr	discere:fishbase_class:7"
}

test_inaturalist_validation_fails_on_rejection_with_mapping() {
    create_mini_reference_db
    write_taxa_file "$OCELLARIS" "101	$POMACENTRIDAE	10	species	Amphiprion bicolor	true"
    run_broken_plugin import.sh \
        "WHERE entity_key NOT IN (SELECT entity_id FROM entity_external_ids WHERE provider = '\${PLUGIN_SOURCE}');" \
        "WHERE 1;"
    assert_status 1
    assert_contains "$ERR" "discere:fishbase_species:1	100	ablehnung mit zuordnung	ambiguous"
}

add_frenata_synonym() {
    sqlite3 "$DB" "INSERT INTO species_scientific_names
        (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
        ('discere:fishbase_species:5', 'Amphiprion frenata', 'amphiprion frenata', 'synonym', 'fishbase', 0);"
}
