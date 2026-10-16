#!/usr/bin/env bash
# Tests für den DuckDB-Export des SeaLifeBase-Plugins
# (plugins/sealifebase/sql/export.sql) mit kleinen synthetischen
# Parquet-Dateien. Die Dateien tragen nur die Spalten, die export.sql liest.

# Legt unter $TEST_TMP/sealifebase die Parquet-Dateien eines Mini-SeaLifeBase
# an:
#
#   Klasse 1 › Ordnung 1 › Familie 1 Semelidae
#   › Gattung 1 Abra, Gattungen 2 und 3 beide „Duplo“
#   Arten:
#     10 Abra alba         GenCode 1
#     11 Abra tenuis       ohne GenCode, Name trifft genau Gattung 1
#     12 Duplo ambiguus    ohne GenCode, Name trifft Gattung 2 und 3
#     13 Nullus ignotus    ohne GenCode, Name trifft keine Gattung
#     14 DummyGenus DummySpecies, der Platzhalter von SeaLifeBase, mit
#        Volksname, Ökologie, Verbreitung und Bild
create_sealifebase_parquets() {
    local dir="$TEST_TMP/sealifebase"
    mkdir -p "$dir"
    duckdb << SQL
CREATE TABLE classes (ClassNum INTEGER, Class VARCHAR, Phylum VARCHAR, CommonName VARCHAR);
INSERT INTO classes VALUES (1, 'Bivalvia', 'Mollusca', NULL);

CREATE TABLE orders (Ordnum INTEGER, "Order" VARCHAR, SisterOrder VARCHAR, ClassNum INTEGER, CommonName VARCHAR,
    CommonName_German VARCHAR, CommonName_French VARCHAR, CommonName_Spanish VARCHAR);
INSERT INTO orders VALUES (1, 'Cardiida', NULL, 1, NULL, NULL, NULL, NULL);

CREATE TABLE families (FamCode INTEGER, Family VARCHAR, Division VARCHAR, Ordnum INTEGER, CommonName VARCHAR,
    CommonName_German VARCHAR, CommonName_French VARCHAR, CommonName_Spanish VARCHAR);
INSERT INTO families VALUES (1, 'Semelidae', NULL, 1, NULL, NULL, NULL, NULL);

CREATE TABLE genera (GenCode INTEGER, GenName VARCHAR, Subfamily VARCHAR, FamCode INTEGER, CommonName VARCHAR);
INSERT INTO genera VALUES (1, 'Abra',  NULL, 1, NULL),
                          (2, 'Duplo', NULL, 1, NULL),
                          (3, 'Duplo', NULL, 1, NULL);

CREATE TABLE species (SpecCode INTEGER, Genus VARCHAR, Species VARCHAR, GenCode INTEGER, Length DOUBLE,
    DepthRangeShallow INTEGER, DepthRangeComShallow INTEGER, DepthRangeDeep INTEGER, DepthRangeComDeep INTEGER,
    DemersPelag VARCHAR, Vulnerability DOUBLE, Dangerous VARCHAR, Importance VARCHAR, LongevityWild FLOAT,
    BodyShapeI VARCHAR);
INSERT INTO species VALUES
    (10, 'Abra',       'alba',         1,    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (11, 'Abra',       'tenuis',       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (12, 'Duplo',      'ambiguus',     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (13, 'Nullus',     'ignotus',      NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (14, 'DummyGenus', 'DummySpecies', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);

CREATE TABLE synonyms (SpecCode INTEGER, SynGenus VARCHAR, SynSpecies VARCHAR, SynonymsRef INTEGER,
    TaxonLevel VARCHAR, Status VARCHAR, Synonymy VARCHAR, Combination VARCHAR, Misspelling INTEGER);
INSERT INTO synonyms VALUES (14, 'Abra', 'vetus', NULL, 'Species', 'synonym', NULL, NULL, 0);

CREATE TABLE comnames (ComName VARCHAR, SpecCode INTEGER, C_Code VARCHAR, Language VARCHAR, NameType VARCHAR,
    PreferredName TINYINT, Rank SMALLINT);
INSERT INTO comnames VALUES ('Dummy clam', 14, '9999', 'English', 'Vernacular', 1, 1),
                            ('White furrow shell', 10, '9999', 'English', 'Vernacular', 1, 1);

CREATE TABLE ecology (SpecCode INTEGER, FoodTroph DOUBLE, FreshWater TINYINT, Stream TINYINT, Lakes TINYINT,
    Mangroves TINYINT, Estuaries TINYINT, SeaGrassBeds TINYINT, CoralReefs TINYINT, Lagoons TINYINT, caves TINYINT,
    Cave TINYINT, Oceanic TINYINT, Epipelagic TINYINT, mesopelagic TINYINT, HardBottom TINYINT, SoftBottom TINYINT,
    Demersal TINYINT, Pelagic TINYINT, Benthic TINYINT, LittoralZone TINYINT, Neritic TINYINT);
INSERT INTO ecology VALUES
    (14, NULL, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    (10, NULL, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

CREATE TABLE country (SpecCode INTEGER, C_Code VARCHAR, Status VARCHAR, CurrentPresence VARCHAR,
    Threatened TINYINT, Abundance VARCHAR, Importance VARCHAR, Comments VARCHAR);
INSERT INTO country VALUES (14, '276', 'native', 'present', 0, NULL, NULL, NULL),
                           (10, '276', 'native', 'present', 0, NULL, NULL, NULL);

CREATE TABLE countrysub (SpecCode INTEGER, C_Code VARCHAR, CSub_Code VARCHAR, Status VARCHAR,
    CurrentPresence VARCHAR, Abundance VARCHAR, Comments VARCHAR);
INSERT INTO countrysub VALUES (14, '276', '1', 'native', 'present', NULL, NULL),
                              (10, '276', '1', 'native', 'present', NULL, NULL);

CREATE TABLE picturesmain (SpecCode INTEGER, PicName VARCHAR, PictureType VARCHAR, LifeStage VARCHAR,
    AuthName VARCHAR, Copyright VARCHAR);
INSERT INTO picturesmain VALUES (14, 'dummy_u0.jpg', 'photo', 'adults', NULL, 'free use'),
                                (10, 'abalb_u0.jpg', 'photo', 'adults', NULL, 'free use');

COPY classes      TO '$dir/classes.parquet'      (FORMAT parquet);
COPY orders       TO '$dir/orders.parquet'       (FORMAT parquet);
COPY families     TO '$dir/families.parquet'     (FORMAT parquet);
COPY genera       TO '$dir/genera.parquet'       (FORMAT parquet);
COPY species      TO '$dir/species.parquet'      (FORMAT parquet);
COPY synonyms     TO '$dir/synonyms.parquet'     (FORMAT parquet);
COPY comnames     TO '$dir/comnames.parquet'     (FORMAT parquet);
COPY ecology      TO '$dir/ecology.parquet'      (FORMAT parquet);
COPY country      TO '$dir/country.parquet'      (FORMAT parquet);
COPY countrysub   TO '$dir/countrysub.parquet'   (FORMAT parquet);
COPY picturesmain TO '$dir/picturesmain.parquet' (FORMAT parquet);
SQL
}

# Führt export.sql aus wie export_to_csv in plugins/sealifebase/import.sh.
run_sealifebase_export() {
    local sql
    mkdir -p "$TEST_TMP/export"
    sql="$(sed \
        -e "s|\${SLB_DIR}|$TEST_TMP/sealifebase|g" \
        -e "s|\${EXPORT_DIR}|$TEST_TMP/export|g" \
        "$ETL_DIR/plugins/sealifebase/sql/export.sql")"
    run_capture duckdb "$TEST_TMP/export/tmp.duckdb" -c "$sql"
}

# Spalten <n> der Datenzeilen von <csv>, sortiert.
slb_csv_columns() {
    tail -n +2 "$TEST_TMP/export/$1.csv" | cut -d , -f "$2" | sort
}

# Fehlt GenCode, gilt die einzige Gattung des Namens; ein Name zweier
# Gattungen und ein Name ohne Gattung lassen die Gattung leer. Den vollen
# wissenschaftlichen Namen bekommt nur, wessen Gattung feststeht.
test_sealifebase_export_resolves_missing_genus_code_by_unique_name() {
    create_sealifebase_parquets
    run_sealifebase_export
    assert_status 0
    assert_eq "discere:sealifebase_species:10,discere:sealifebase_genus:1
discere:sealifebase_species:11,discere:sealifebase_genus:1
discere:sealifebase_species:12,
discere:sealifebase_species:13," "$(slb_csv_columns species 1,15)" "Gattung je Art"
    assert_eq "discere:sealifebase_species:10,Abra alba
discere:sealifebase_species:11,Abra tenuis" "$(slb_csv_columns species_scientific_names 1,2)" \
        "wissenschaftliche Namen"
}

# Der Platzhalter „DummyGenus DummySpecies“ ist kein Taxon: weder die Art noch
# ihre Synonyme, Volksnamen, Merkmale, Verbreitung oder Bilder kommen in den
# Export.
test_sealifebase_export_skips_dummy_species_and_its_contributions() {
    create_sealifebase_parquets
    run_sealifebase_export
    assert_status 0
    assert_not_contains "$(cat "$TEST_TMP/export/species.csv")" "sealifebase_species:14"
    assert_eq "discere:sealifebase_species:10,White furrow shell" \
        "$(slb_csv_columns common_names 1,5 | grep species)" "Volksnamen"
    assert_eq "discere:sealifebase_species:10" "$(slb_csv_columns taxonomy_traits 1 | uniq)" "Merkmale"
    assert_eq "discere:sealifebase_species:10
discere:sealifebase_species:10" "$(slb_csv_columns taxonomy_distribution_regions 1)" "Verbreitung"
    assert_eq "discere:sealifebase_species:10" "$(slb_csv_columns pictures 2)" "Bilder"
    assert_not_contains "$(cat "$TEST_TMP/export/species_scientific_names.csv")" "vetus"
}

# Der Build-Bericht nennt jede Art, deren Gattung über den Namen aufgelöst
# wurde, und jede, die offen blieb, samt Grund; Arten mit GenCode und den
# Platzhalter nicht.
test_sealifebase_export_reports_genus_resolution() {
    create_sealifebase_parquets
    run_sealifebase_export
    assert_status 0
    assert_eq "genus_by_name	11	Abra tenuis	GenCode 1
genus_unresolved	12	Duplo ambiguus	2 Gattungen dieses Namens
genus_unresolved	13	Nullus ignotus	keine Gattung dieses Namens" \
        "$(cat "$TEST_TMP/export/genus_report.tsv")" "Bericht"
}

# Ersetzt synonyms.parquet durch Synonyme von Abra alba (Art 10), die mit
# ihrem kanonischen Namen oder untereinander denselben normalisierten Namen
# tragen, in der Reihenfolge <ASC|DESC>:
#   abra alba     synonym (Ref 5), ambiguous synonym „Alba “ (Ref 6)
#   abra nitida   misapplied name (Ref 1), ambiguous synonym (Ref 2),
#                 synonym (Ref 4)
#   abra ovata    synonym (Ref 12), synonym (Ref 11)
write_colliding_sealifebase_synonyms() {
    duckdb << SQL
COPY (
    SELECT SpecCode, SynGenus, SynSpecies, SynonymsRef, 'Species' AS TaxonLevel, Status,
           NULL::VARCHAR AS Synonymy, NULL::VARCHAR AS Combination, 0 AS Misspelling
    FROM (VALUES
        (1, 10, 'Abra', 'alba',   5,  'synonym'),
        (2, 10, 'Abra', 'Alba ',  6,  'ambiguous synonym'),
        (3, 10, 'Abra', 'nitida', 1,  'misapplied name'),
        (4, 10, 'Abra', 'nitida', 2,  'ambiguous synonym'),
        (5, 10, 'Abra', 'nitida', 4,  'synonym'),
        (6, 10, 'Abra', 'ovata',  12, 'synonym'),
        (7, 10, 'Abra', 'ovata',  11, 'synonym')
    ) AS t(pos, SpecCode, SynGenus, SynSpecies, SynonymsRef, Status)
    ORDER BY pos $1
) TO '$TEST_TMP/sealifebase/synonyms.parquet' (FORMAT parquet);
SQL
}

# Je Art und normalisiertem Namen eine Zeile: Der kanonische Name bleibt
# bevorzugt, auch wenn die Quelle ihn zusätzlich als Synonym führt; unter
# gleichnamigen Synonymen entscheidet erst der Status, dann source_ref — in
# jeder Reihenfolge der Eingabe gleich.
test_sealifebase_export_keeps_one_name_per_species_canonical_first() {
    local expected="abra alba,valid,10,1
abra nitida,synonym,4,0
abra ovata,synonym,11,0"
    local order
    create_sealifebase_parquets
    for order in ASC DESC; do
        write_colliding_sealifebase_synonyms "$order"
        run_sealifebase_export
        assert_status 0
        assert_eq "$expected" "$(slb_csv_columns species_scientific_names 1,3,4,6,7 \
            | sed -n 's/^discere:sealifebase_species:10,//p')" \
            "wissenschaftliche Namen ($order)"
    done
}
