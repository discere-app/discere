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
    sql="$(source "$ETL_DIR/core/plugin_api.sh"; PLUGIN_CORE_DIR="$ETL_DIR/core"
        plugin_render_sql "$ETL_DIR/plugins/fishbase/sql/export.sql" | sed \
        -e "s|\${FISHBASE_DIR}|$TEST_TMP/fishbase|g" \
        -e "s|\${PARQUET_DIR}|$TEST_TMP/fishbase|g" \
        -e "s|\${EXPORT_DIR}|$TEST_TMP/export|g" \
        -e "s|\${PLACEHOLDER_PATTERNS}|$ETL_DIR/core/data/placeholder_patterns.csv|g")"
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

# Ersetzt synonyms.parquet durch Synonyme von Amphiprion ocellaris (Art 2),
# die mit ihrem kanonischen Namen oder untereinander denselben
# normalisierten Namen tragen, in der Reihenfolge <ASC|DESC>; Ebene Species,
# wo nicht anders genannt:
#   amphiprion ocellaris  ambiguous synonym (Ref 5), synonym „Ocellaris “ (Ref 6)
#   amphiprion bicolor    misapplied name (Ref 1), ambiguous synonym (Ref 2),
#                         synonym (Ref 4)
#   amphiprion melanurus  synonym (Ref 12), synonym auf der Ebene „species“
#                         (Ref 11)
#   amphiprion percula    synonym nur auf der Ebene „species“ (Ref 7)
write_colliding_fishbase_synonyms() {
    duckdb << SQL
COPY (
    SELECT SpecCode, SynGenus, SynSpecies, NULL::VARCHAR AS Author, SynonymsRef, TaxonLevel,
           NULL::VARCHAR AS Comment, Status, 0 AS Valid, NULL::VARCHAR AS Synonymy,
           NULL::VARCHAR AS Combination, 0 AS Misspelling
    FROM (VALUES
        (1, 2, 'Amphiprion', 'ocellaris',  5,  'Species', 'ambiguous synonym'),
        (2, 2, 'Amphiprion', 'Ocellaris ', 6,  'Species', 'synonym'),
        (3, 2, 'Amphiprion', 'bicolor',    1,  'Species', 'misapplied name'),
        (4, 2, 'Amphiprion', 'bicolor',    2,  'Species', 'ambiguous synonym'),
        (5, 2, 'Amphiprion', 'bicolor',    4,  'Species', 'synonym'),
        (6, 2, 'Amphiprion', 'melanurus',  12, 'Species', 'synonym'),
        (7, 2, 'Amphiprion', 'melanurus',  11, 'species', 'synonym'),
        (8, 2, 'Amphiprion', 'percula',    7,  'species', 'synonym')
    ) AS t(pos, SpecCode, SynGenus, SynSpecies, SynonymsRef, TaxonLevel, Status)
    ORDER BY pos $1
) TO '$TEST_TMP/fishbase/synonyms.parquet' (FORMAT parquet);
SQL
}

# Normalisierter Name, Status, source_ref und is_preferred je exportierter Zeile.
fishbase_scientific_name_rows() {
    csv_column species_scientific_names 3,4,6,7
}

# Je Art und normalisiertem Namen eine Zeile: Der kanonische Name bleibt
# bevorzugt, auch wenn die Quelle ihn zusätzlich als Synonym führt; unter
# gleichnamigen Synonymen entscheidet erst der Status, dann source_ref — in
# jeder Reihenfolge der Eingabe gleich. Die Ebene Species zählt in jeder
# Schreibweise, auch wenn derselbe Name auf beiden steht.
test_fishbase_export_keeps_one_name_per_species_canonical_first() {
    local expected="amphiprion bicolor,synonym,4,0
amphiprion melanurus,synonym,11,0
amphiprion ocellaris,valid,2,1
amphiprion percula,synonym,7,0"
    local order
    create_fishbase_parquets
    for order in ASC DESC; do
        write_colliding_fishbase_synonyms "$order"
        run_fishbase_export
        assert_status 0
        assert_eq "$expected" "$(fishbase_scientific_name_rows)" "wissenschaftliche Namen ($order)"
    done
}

# Vergibt Ordnum 1 ein zweites Mal, an Carcharhiniformes in der Klasse 8
# Elasmobranchii, mit der Familie 3 Carcharhinidae ohne Arten darunter.
write_duplicate_fishbase_order() {
    local dir="$TEST_TMP/fishbase"
    duckdb << SQL
CREATE TABLE classes AS SELECT * FROM '$dir/classes.parquet';
INSERT INTO classes VALUES (8, 'Elasmobranchii', NULL, NULL, 'Chondrichthyes');
CREATE TABLE orders AS SELECT * FROM '$dir/orders.parquet';
INSERT INTO orders VALUES (1, 'Carcharhiniformes', NULL, NULL, 0, 8, 'Elasmobranchii', NULL, NULL, NULL, NULL);
CREATE TABLE families AS SELECT * FROM '$dir/families.parquet';
INSERT INTO families VALUES (3, 'Carcharhinidae', NULL, 'Carcharhiniformes', 1, 'Elasmobranchii', 8, 0, 0, NULL,
    false, NULL, NULL, NULL, NULL, NULL, NULL);
COPY classes  TO '$dir/classes.parquet'  (FORMAT parquet);
COPY orders   TO '$dir/orders.parquet'   (FORMAT parquet);
COPY families TO '$dir/families.parquet' (FORMAT parquet);
SQL
}

# Doppelte Codes behandelt FishBase nach derselben Regel wie SeaLifeBase
# (core/sql/source_codes.sql): Entität wird die Ordnung, an deren Familien
# Arten hängen; die Familie, die die andere nennt, bleibt ohne Ordnung.
test_fishbase_export_resolves_duplicate_order_code() {
    create_fishbase_parquets
    write_duplicate_fishbase_order
    run_fishbase_export
    assert_status 0
    assert_eq "discere:fishbase_order:1,Ovalentaria" "$(csv_column orders 1,4)" "Ordnungen"
    assert_eq "discere:fishbase_family:1,discere:fishbase_order:1
discere:fishbase_family:3," "$(csv_column families 1,7)" "Ordnung je Familie"
    assert_eq "code_duplicate	Ordnum 1	Carcharhiniformes	2 Zeilen; nicht exportiert, Schlüssel bei Ovalentaria
code_duplicate	Ordnum 1	Ovalentaria	2 Zeilen; Entität unter diesem Schlüssel (einzige Zeile mit Arten)
family_order_rejected	3	Carcharhinidae	Ordnum 1 doppelt, Familie nennt Carcharhiniformes (ClassNum 8): Ordnung Carcharhiniformes nicht exportiert
family_order_resolved	1	Pomacentridae	Ordnum 1 doppelt, Familie nennt Ovalentaria (ClassNum 7): Ordnung Ovalentaria" \
        "$(cat "$TEST_TMP/export/code_report.tsv")" "Bericht"
}
