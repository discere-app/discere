#!/usr/bin/env bash
# Tests für plugins/inaturalist/import.sh gegen die Mini-DB aus lib.sh und
# eine kleine taxa.csv.gz (ohne Download)

write_taxa_file() {
    {
        printf 'taxon_id\tancestry\trank_level\trank\tname\tactive\n'
        printf '%s\n' "$@"
    } | gzip > "$TEST_TMP/taxa.csv.gz"
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
        $'100\t1\t10\tspecies\tAmphiprion ocellaris\ttrue' \
        $'101\t1\t10\tspecies\tAmphiprion bicolor\ttrue' \
        $'102\t1\t10\tspecies\tAmphiprion percula\ttrue' \
        $'103\t1\t10\tspecies\tAmphiprion communis\ttrue' \
        $'104\t1\t20\tgenus\tAmphiprion\ttrue' \
        $'105\t2\t20\tgenus\tAmphiprion\ttrue' \
        $'106\t1\t30\tfamily\tPomacentridae\ttrue' \
        $'107\t1\t50\tclass\tTeleostei\ttrue' \
        $'108\t1\t10\tspecies\tAmphiprion clarkii\tfalse' \
        $'109\t1\t10\tspecies\tHomo sapiens\ttrue' \
        $'110\t1\t40\torder\tOvalentaria\ttrue'
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
inaturalist	ambiguous	104, 105	Amphiprion	mehrere aktive iNaturalist-Taxa auf Rang genus" \
        "$(tail -n +2 "$TEST_TMP/report/inaturalist.tsv" | LC_ALL=C sort)" "Build-Bericht"
    assert_eq "inaturalist|CC BY / CC0|https://www.inaturalist.org/taxa/{external_id}" \
        "$(sqlite3 "$DB" "SELECT id, license_key, species_url_template FROM sources WHERE id = 'inaturalist';")" \
        "sources-Eintrag"
}

test_inaturalist_reimport_replaces_its_mappings() {
    create_mini_reference_db
    write_taxa_file $'100\t1\t10\tspecies\tAmphiprion ocellaris\ttrue'
    run_inaturalist_import
    assert_status 0
    write_taxa_file $'102\t1\t10\tspecies\tAmphiprion percula\ttrue'
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
