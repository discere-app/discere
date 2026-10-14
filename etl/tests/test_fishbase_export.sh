#!/usr/bin/env bash
# Tests für den DuckDB-Export des FishBase-Plugins (plugins/fishbase/sql/export.sql)
# mit kleinen synthetischen Parquet-Dateien. Die Dateien tragen nur die
# Spalten, die export.sql liest.

# Legt unter $TEST_TMP/fishbase die Parquet-Dateien eines Mini-FishBase an:
#
#   Klasse 7 › Ordnung 1 › Familie 1 Pomacentridae
#   › Gattung 1 Amphiprion: Art 2 ocellaris (Synonym Amphiprion bicolor)
#   Platzhalter wie in FishBase: Familie 0 „Family“ (Volksname „New family“)
#   › Gattung 0 „Genus“ (Volksname „New species“) mit den Arten 0 „Species“
#   (Synonym Amphiprion vetus) und 1 „Sp“
#
# Beide Arten 0 und 2 haben Volksnamen, Ökologie, Verbreitung und Bilder.
create_fishbase_parquets() {
    local dir="$TEST_TMP/fishbase"
    mkdir -p "$dir"
    duckdb << SQL
CREATE TABLE classes (ClassNum INTEGER, Class VARCHAR, CommonName VARCHAR, BodyShapeI VARCHAR, SuperClass VARCHAR);
INSERT INTO classes VALUES (7, 'Teleostei', NULL, NULL, 'Actinopterygii');

CREATE TABLE orders (Ordnum INTEGER, "Order" VARCHAR, CommonName VARCHAR, BodyShapeI VARCHAR, Freshwater TINYINT,
    ClassNum INTEGER, Class VARCHAR, SisterOrder VARCHAR, CommonName_German VARCHAR, CommonName_French VARCHAR,
    CommonName_Spanish VARCHAR);
INSERT INTO orders VALUES (1, 'Ovalentaria', NULL, NULL, 0, 7, 'Teleostei', NULL, NULL, NULL, NULL);

CREATE TABLE families (FamCode INTEGER, Family VARCHAR, CommonName VARCHAR, "Order" VARCHAR, Ordnum SMALLINT,
    Class VARCHAR, ClassNum SMALLINT, Genera SMALLINT, Species SMALLINT, BodyShapeI VARCHAR, Freshwater BOOLEAN,
    Aquarium VARCHAR, Source VARCHAR, Division VARCHAR, CommonName_German VARCHAR, CommonName_French VARCHAR,
    CommonName_Spanish VARCHAR);
INSERT INTO families VALUES
    (0, 'Family',        'New family', 'Order',       0, 'Class',     0, 1, 2, NULL, false,
     NULL, NULL, NULL, NULL, NULL, NULL),
    (1, 'Pomacentridae', NULL,         'Ovalentaria', 1, 'Teleostei', 7, 1, 1, NULL, false,
     NULL, NULL, NULL, NULL, NULL, NULL);

CREATE TABLE genera (GenCode INTEGER, GenName VARCHAR, GenComName VARCHAR, FamCode SMALLINT, Subfamily VARCHAR,
    BodyShapeI VARCHAR, Length FLOAT, DepthRangeShallow SMALLINT, DepthRangeDeep SMALLINT,
    DepthRangeComShallow SMALLINT, DepthRangeComDeep SMALLINT, Comment VARCHAR, Distribution VARCHAR,
    Habitat VARCHAR, Freshwater BOOLEAN);
INSERT INTO genera VALUES
    (0, 'Genus',      'New species',   0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, false),
    (1, 'Amphiprion', 'anemonefishes', 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, false);

CREATE TABLE species (SpecCode INTEGER, Genus VARCHAR, Species VARCHAR, Author VARCHAR, FamCode INTEGER,
    Subfamily VARCHAR, GenCode INTEGER, BodyShapeI VARCHAR, Source VARCHAR, DemersPelag VARCHAR,
    DepthRangeShallow SMALLINT, DepthRangeDeep SMALLINT, DepthRangeComShallow SMALLINT, DepthRangeComDeep SMALLINT,
    LongevityWild FLOAT, Vulnerability DOUBLE, Length FLOAT, Pic VARCHAR, Importance VARCHAR, Aquarium VARCHAR,
    Dangerous VARCHAR, Comments VARCHAR);
INSERT INTO species VALUES
    (0, 'Genus',      'Species',   'Bailly, 2020', 0, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (1, 'Genus',      'Sp',        'Bailly, 2020', 0, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (2, 'Amphiprion', 'ocellaris', 'Cuvier, 1830', 1, NULL, 1, NULL, NULL, 'reef-associated', NULL, NULL, NULL, NULL, NULL, NULL, 11, NULL, NULL, NULL, NULL, NULL);

CREATE TABLE synonyms (SpecCode INTEGER, SynGenus VARCHAR, SynSpecies VARCHAR, Author VARCHAR, SynonymsRef INTEGER,
    TaxonLevel VARCHAR, Comment VARCHAR, Status VARCHAR, Valid INTEGER, Synonymy VARCHAR, Combination VARCHAR,
    Misspelling INTEGER);
INSERT INTO synonyms VALUES
    (0, 'Amphiprion', 'vetus',   NULL, NULL, 'Species', NULL, 'synonym', 0, NULL, NULL, 0),
    (2, 'Amphiprion', 'bicolor', NULL, NULL, 'Species', NULL, 'synonym', 0, NULL, NULL, 0);

CREATE TABLE comnames (ComName VARCHAR, SpecCode INTEGER, C_Code VARCHAR, Language VARCHAR, NameType VARCHAR,
    PreferredName TINYINT, Misspelling TINYINT, Rank SMALLINT);
INSERT INTO comnames VALUES
    ('Platzhalterfisch',  0, '9999', 'German', 'Vernacular', 1, 0, 1),
    ('Clown anemonefish', 2, '9999', 'English', 'Vernacular', 1, 0, 1);

CREATE TABLE ecology (SpecCode INTEGER, Neritic TINYINT, LittoralZone TINYINT, Caves TINYINT, Oceanic TINYINT,
    Epipelagic TINYINT, Mesopelagic TINYINT, Estuaries TINYINT, Mangroves TINYINT, Stream TINYINT, Lakes TINYINT,
    Cave TINYINT, FoodTroph DOUBLE, Benthic TINYINT, Demersal TINYINT, Pelagic TINYINT, SoftBottom TINYINT,
    HardBottom TINYINT, SeaGrassBeds TINYINT, CoralReefs TINYINT, Lagoons TINYINT);
INSERT INTO ecology VALUES
    (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NULL, 0, 0, 0, 0, 0, 0, -1, 0),
    (2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NULL, 0, 0, 0, 0, 0, 0, -1, 0);

CREATE TABLE country (C_Code VARCHAR, SpecCode INTEGER, Status VARCHAR, CurrentPresence VARCHAR, Freshwater TINYINT,
    Comments VARCHAR, Abundance VARCHAR, Importance VARCHAR, Threatened TINYINT);
INSERT INTO country VALUES ('276', 0, 'native', 'present', 0, NULL, NULL, NULL, 0),
                           ('276', 2, 'native', 'present', 0, NULL, NULL, NULL, 0);

CREATE TABLE countrysub (SpecCode INTEGER, C_Code VARCHAR, CSub_Code VARCHAR, Status VARCHAR, CurrentPresence VARCHAR,
    Abundance VARCHAR, Comments VARCHAR);
INSERT INTO countrysub VALUES (0, '276', '1', 'native', 'present', NULL, NULL),
                              (2, '276', '1', 'native', 'present', NULL, NULL);

CREATE TABLE picturesmain (SpecCode INTEGER, PicName VARCHAR, PictureType VARCHAR, Rank SMALLINT, Occurrence TINYINT,
    LifeStage VARCHAR, C_Code VARCHAR, AuthName VARCHAR, URL VARCHAR, Copyright VARCHAR, Comment VARCHAR);
INSERT INTO picturesmain VALUES (0, 'pl_u0.jpg', 'photo', 1, 0, 'adults', NULL, NULL, NULL, 'free use', NULL),
                                (2, 'amocc_u0.jpg', 'photo', 1, 0, 'adults', NULL, NULL, NULL, 'free use', NULL);

CREATE TABLE fieldguide_pic (id INTEGER, Family VARCHAR, SpecCode VARCHAR, Genus VARCHAR, Species VARCHAR, Picname VARCHAR);
INSERT INTO fieldguide_pic VALUES (1, NULL, '0', NULL, NULL, 'pl_fg.gif'),
                                  (2, NULL, '2', NULL, NULL, 'amocc_fg.gif');

COPY classes        TO '$dir/classes.parquet'        (FORMAT parquet);
COPY orders         TO '$dir/orders.parquet'         (FORMAT parquet);
COPY families       TO '$dir/families.parquet'       (FORMAT parquet);
COPY genera         TO '$dir/genera.parquet'         (FORMAT parquet);
COPY species        TO '$dir/species.parquet'        (FORMAT parquet);
COPY synonyms       TO '$dir/synonyms.parquet'       (FORMAT parquet);
COPY comnames       TO '$dir/comnames.parquet'       (FORMAT parquet);
COPY ecology        TO '$dir/ecology.parquet'        (FORMAT parquet);
COPY country        TO '$dir/country.parquet'        (FORMAT parquet);
COPY countrysub     TO '$dir/countrysub.parquet'     (FORMAT parquet);
COPY picturesmain   TO '$dir/picturesmain.parquet'   (FORMAT parquet);
COPY fieldguide_pic TO '$dir/fieldguide_pic.parquet' (FORMAT parquet);
SQL
}

# Führt export.sql aus wie export_to_csv in plugins/fishbase/import.sh.
run_fishbase_export() {
    local sql
    mkdir -p "$TEST_TMP/export"
    sql="$(sed \
        -e "s|\${FISHBASE_DIR}|$TEST_TMP/fishbase|g" \
        -e "s|\${EXPORT_DIR}|$TEST_TMP/export|g" \
        "$ETL_DIR/plugins/fishbase/sql/export.sql")"
    run_capture duckdb "$TEST_TMP/export/tmp.duckdb" -c "$sql"
}

# Spalte <n> der Datenzeilen von <csv>, sortiert.
csv_column() {
    tail -n +2 "$TEST_TMP/export/$1.csv" | cut -d , -f "$2" | sort
}

# Die Platzhalter-Familie 0, -Gattung 0 und ihre Arten 0 und 1 sind keine
# Taxa: Weder sie noch ihre Synonyme, Volksnamen, Merkmale, Verbreitung oder Bilder
# kommen in den Export; Amphiprion ocellaris kommt vollständig.
test_fishbase_export_skips_placeholder_family_genus_and_species() {
    create_fishbase_parquets
    run_fishbase_export
    assert_status 0
    assert_eq "discere:fishbase_family:1" "$(csv_column families 1)" "Familien"
    assert_eq "discere:fishbase_genus:1" "$(csv_column genera 1)" "Gattungen"
    assert_eq "discere:fishbase_species:2" "$(csv_column species 1)" "Arten"
    assert_eq "discere:fishbase_species:2,Amphiprion bicolor
discere:fishbase_species:2,Amphiprion ocellaris" "$(csv_column species_scientific_names 1,2)" "wissenschaftliche Namen"
    assert_eq "discere:fishbase_genus:1,anemonefishes
discere:fishbase_species:2,Clown anemonefish" "$(csv_column common_names 1,5)" "Volksnamen"
    assert_eq "discere:fishbase_species:2" "$(csv_column taxonomy_traits 1 | uniq)" "Merkmale"
    assert_eq "discere:fishbase_species:2
discere:fishbase_species:2" "$(csv_column taxonomy_distribution_regions 1)" "Verbreitung"
    assert_eq "discere:fishbase_species:2
discere:fishbase_species:2" "$(csv_column pictures 2)" "Bilder"
}
