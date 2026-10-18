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

CREATE TABLE families (FamCode INTEGER, Family VARCHAR, Division VARCHAR, Ordnum INTEGER, "Order" VARCHAR,
    ClassNum INTEGER, Phylum VARCHAR, CommonName VARCHAR, CommonName_German VARCHAR, CommonName_French VARCHAR,
    CommonName_Spanish VARCHAR);
INSERT INTO families VALUES (1, 'Semelidae', NULL, 1, 'Cardiida', 1, 'Mollusca', NULL, NULL, NULL, NULL);

CREATE TABLE genera (GenCode INTEGER, GenName VARCHAR, Subfamily VARCHAR, FamCode INTEGER, CommonName VARCHAR);
INSERT INTO genera VALUES (1, 'Abra',  NULL, 1, NULL),
                          (2, 'Duplo', NULL, 1, NULL),
                          (3, 'Duplo', NULL, 1, NULL);

CREATE TABLE species (SpecCode INTEGER, Genus VARCHAR, Species VARCHAR, GenCode INTEGER, FamCode INTEGER, Length DOUBLE,
    DepthRangeShallow INTEGER, DepthRangeComShallow INTEGER, DepthRangeDeep INTEGER, DepthRangeComDeep INTEGER,
    DemersPelag VARCHAR, Vulnerability DOUBLE, Dangerous VARCHAR, Importance VARCHAR, LongevityWild FLOAT,
    BodyShapeI VARCHAR);
INSERT INTO species VALUES
    (10, 'Abra',       'alba',         1,    1,    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (11, 'Abra',       'tenuis',       NULL, 1,    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (12, 'Duplo',      'ambiguus',     NULL, 1,    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (13, 'Nullus',     'ignotus',      NULL, 1,    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (14, 'DummyGenus', 'DummySpecies', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);

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
    sql="$(source "$ETL_DIR/core/plugin_api.sh"; PLUGIN_CORE_DIR="$ETL_DIR/core"
        plugin_render_sql "$ETL_DIR/plugins/sealifebase/sql/export.sql" | sed \
        -e "s|\${SLB_DIR}|$TEST_TMP/sealifebase|g" \
        -e "s|\${PARQUET_DIR}|$TEST_TMP/sealifebase|g" \
        -e "s|\${EXPORT_DIR}|$TEST_TMP/export|g" \
        -e "s|\${PLACEHOLDER_PATTERNS}|$ETL_DIR/core/data/placeholder_patterns.csv|g" \
        -e "s|\${FAMILY_PHYLUM_EQUIVALENTS}|$ETL_DIR/plugins/sealifebase/data/family_phylum_equivalents.csv|g")"
    run_capture duckdb "$TEST_TMP/export/tmp.duckdb" -c "$sql"
}

# Spalten <n> der Datenzeilen von <csv>, sortiert.
slb_csv_columns() {
    tail -n +2 "$TEST_TMP/export/$1.csv" | cut -d , -f "$2" | sort
}

# Fehlt GenCode, gilt die einzige Gattung des Namens; ein Name zweier
# Gattungen und ein Name ohne Gattung lassen die Gattung leer. Den
# wissenschaftlichen Namen gibt die Quelle der Art auch ohne Gattung.
test_sealifebase_export_resolves_missing_genus_code_by_unique_name() {
    create_sealifebase_parquets
    run_sealifebase_export
    assert_status 0
    assert_eq "discere:sealifebase_species:10,discere:sealifebase_genus:1
discere:sealifebase_species:11,discere:sealifebase_genus:1
discere:sealifebase_species:12,
discere:sealifebase_species:13," "$(slb_csv_columns species 1,15)" "Gattung je Art"
    assert_eq "discere:sealifebase_species:10,Abra alba
discere:sealifebase_species:11,Abra tenuis
discere:sealifebase_species:12,Duplo ambiguus
discere:sealifebase_species:13,Nullus ignotus" "$(slb_csv_columns species_scientific_names 1,2)" \
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

# Ersetzt Klassen, Ordnungen, Familien, Gattungen und Arten durch eine
# Taxonomie, in der Gattung (GenCode) und Familie der Art (FamCode)
# auseinanderlaufen und die Quelle Codes mehrfach vergibt:
#
#   Mollusca      › Bivalvia (1)       › Cardiida (1)    › Semelidae (1), Tellinidae (2)
#                                      › Venerida (2)    › Veneridae (3)
#                 › Gastropoda (2)     › Neogastropoda (5) › Muricidae (6)
#   Cnidaria      › Hydrozoa (3)       › Leptothecata (3)  › Halopterididae (4)
#   Rhodophyta    › Florideophyceae (4) › Ceramiales (4)   › Ceramiaceae (5)
#   Mollusca      › Not assigned (5)   › Not assigned (6)  › Fooidae (9), Barridae (10)
#   Arthropoda    › Arachnida (6)
#   Echinodermata › Echinoidea (7)
#   Orphanidae (8) zeigt auf eine Ordnung, die es nicht gibt.
#
#   Ordnum 7, zweimal vergeben: Ostreida (Bivalvia) und Araneae (Arachnida)
#     Ambigidae (7)  nennt Ostreida, Bivalvia    → Ostreida, hält Arten
#     Desidae (11)   nennt Araneae, Arachnida    → Araneae, ohne Arten
#     Mixtidae (12)  nennt Ostreida, Gastropoda  → keine Zeile passt
#   Ordnum 8, zweimal vergeben: Phymosomatoida (Echinoidea) und Not assigned
#   (Not assigned)
#     Chromidae (13) nennt Not assigned, Klasse 5 → Not assigned, ohne Arten
#   GenCode 10, zweimal vergeben: Dupla und Duplex (beide Semelidae)
#
#   Gattungen: 1 Abra (1), 2 Tellina (2), 3 Venus (3), 4 Gattya (5),
#   5 Murex (6), 6 Halistemma (4), 7 Ambix (7), 8 Solus (1), 9 Placo (10)
#
#   Art                          GenCode  FamCode  Fall
#   10 Abra alba                 1        1        passt
#   20 Tellina tenuis            2        1        nur Familie anders
#   21 Venus verrucosa           3        1        Ordnung anders, Klasse gleich
#   22 Gattya humilis            4        4        anderer Stamm
#   23 Murex brandaris           5        1        andere Klasse
#   24 Stephanomia amphytridis   6        4        Gattung heißt anders
#   25 Ambix dubius              7        1        Ordnung der Gattung über den
#                                                  doppelten Ordnum aufgelöst,
#                                                  anders, Klasse gleich
#   32 Ambix aranea              7        6        Ordnung der Gattung
#                                                  aufgelöst, andere Klasse
#   28 Abra orba                 1        8        Ordnung der Art unbekannt
#   33 Abra mixta                1        12       Ordnung der Art unter dem
#                                                  doppelten Ordnum nicht
#                                                  auflösbar
#   29 Ambix certus              7        7        passt (gleiche Familie)
#   31 Placo incertus            9        9        Familie anders, beide in der
#                                                  Platzhalter-Klasse
#   26 Solus novus               —        1        über den Namen, passt
#   27 Abra rara                 —        5        über den Namen, anderer Stamm
#   30 Tellina nova              —        1        über den Namen, nur Familie
#                                                  anders
write_genus_check_parquets() {
    local dir="$TEST_TMP/sealifebase"
    duckdb << SQL
COPY (SELECT ClassNum, Class, Phylum, NULL::VARCHAR AS CommonName FROM (VALUES
    (1, 'Bivalvia', 'Mollusca'), (2, 'Gastropoda', 'Mollusca'),
    (3, 'Hydrozoa', 'Cnidaria'), (4, 'Florideophyceae', 'Rhodophyta'),
    (5, 'Not assigned', 'Mollusca'), (6, 'Arachnida', 'Arthropoda'),
    (7, 'Echinoidea', 'Echinodermata')
) AS t(ClassNum, Class, Phylum)) TO '$dir/classes.parquet' (FORMAT parquet);

COPY (SELECT Ordnum, "Order", NULL::VARCHAR AS SisterOrder, ClassNum, NULL::VARCHAR AS CommonName,
             NULL::VARCHAR AS CommonName_German, NULL::VARCHAR AS CommonName_French,
             NULL::VARCHAR AS CommonName_Spanish
      FROM (VALUES (1, 'Cardiida', 1), (2, 'Venerida', 1), (7, 'Ostreida', 1), (7, 'Araneae', 6),
                   (8, 'Phymosomatoida', 7), (8, 'Not assigned', 5),
                   (5, 'Neogastropoda', 2), (3, 'Leptothecata', 3), (4, 'Ceramiales', 4),
                   (6, 'Not assigned', 5)
      ) AS t(Ordnum, "Order", ClassNum)) TO '$dir/orders.parquet' (FORMAT parquet);

COPY (SELECT FamCode, Family, NULL::VARCHAR AS Division, Ordnum, "Order", ClassNum, Phylum,
             NULL::VARCHAR AS CommonName, NULL::VARCHAR AS CommonName_German,
             NULL::VARCHAR AS CommonName_French, NULL::VARCHAR AS CommonName_Spanish
      FROM (VALUES (1, 'Semelidae', 1, 'Cardiida', 1, 'Mollusca'), (2, 'Tellinidae', 1, 'Cardiida', 1, 'Mollusca'),
                   (3, 'Veneridae', 2, 'Venerida', 1, 'Mollusca'), (7, 'Ambigidae', 7, 'Ostreida', 1, 'Mollusca'),
                   (11, 'Desidae', 7, 'Araneae', 6, 'Arthropoda'), (12, 'Mixtidae', 7, ' ostreida', 2, 'Mollusca'),
                   (13, 'Chromidae', 8, 'Not assigned', 5, 'Mollusca'),
                   (6, 'Muricidae', 5, 'Neogastropoda', 2, 'Mollusca'),
                   (4, 'Halopterididae', 3, 'Leptothecata', 3, 'Cnidaria'),
                   (5, 'Ceramiaceae', 4, 'Ceramiales', 4, 'Rhodophyta'),
                   (8, 'Orphanidae', 99, 'Unknownida', 1, 'Mollusca'),
                   (9, 'Fooidae', 6, 'Not assigned', 5, 'Mollusca'), (10, 'Barridae', 6, 'Not assigned', 5, 'Mollusca')
      ) AS t(FamCode, Family, Ordnum, "Order", ClassNum, Phylum)) TO '$dir/families.parquet' (FORMAT parquet);

COPY (SELECT GenCode, GenName, NULL::VARCHAR AS Subfamily, FamCode, NULL::VARCHAR AS CommonName
      FROM (VALUES (1, 'Abra', 1), (2, 'Tellina', 2), (3, 'Venus', 3), (4, 'Gattya', 5),
                   (5, 'Murex', 6), (6, 'Halistemma', 4), (7, 'Ambix', 7), (8, 'Solus', 1),
                   (9, 'Placo', 10), (10, 'Dupla', 1), (10, 'Duplex', 1)
      ) AS t(GenCode, GenName, FamCode)) TO '$dir/genera.parquet' (FORMAT parquet);

COPY (SELECT SpecCode, Genus, Species, GenCode, FamCode, NULL::DOUBLE AS Length,
             NULL::INTEGER AS DepthRangeShallow, NULL::INTEGER AS DepthRangeComShallow,
             NULL::INTEGER AS DepthRangeDeep, NULL::INTEGER AS DepthRangeComDeep,
             NULL::VARCHAR AS DemersPelag, NULL::DOUBLE AS Vulnerability, NULL::VARCHAR AS Dangerous,
             NULL::VARCHAR AS Importance, NULL::FLOAT AS LongevityWild, NULL::VARCHAR AS BodyShapeI
      FROM (VALUES
          (10, 'Abra',        'alba',        1,    1),
          (20, 'Tellina',     'tenuis',      2,    1),
          (21, 'Venus',       'verrucosa',   3,    1),
          (22, 'Gattya',      'humilis',     4,    4),
          (23, 'Murex',       'brandaris',   5,    1),
          (24, 'Stephanomia', 'amphytridis', 6,    4),
          (25, 'Ambix',       'dubius',      7,    1),
          (26, 'Solus',       'novus',       NULL, 1),
          (27, 'Abra',        'rara',        NULL, 5),
          (28, 'Abra',        'orba',        1,    8),
          (29, 'Ambix',       'certus',      7,    7),
          (30, 'Tellina',     'nova',        NULL, 1),
          (31, 'Placo',       'incertus',    9,    9),
          (32, 'Ambix',       'aranea',      7,    6),
          (33, 'Abra',        'mixta',       1,    12)
      ) AS t(SpecCode, Genus, Species, GenCode, FamCode)) TO '$dir/species.parquet' (FORMAT parquet);
SQL
}

# Exportiert die Taxonomie aus write_genus_check_parquets.
run_genus_check_export() {
    create_sealifebase_parquets
    write_genus_check_parquets
    run_sealifebase_export
    assert_status 0
}

# Vorläufige Gattungs-ID der Art <speccode> in species.csv, leer ohne Gattung.
slb_genus_of() {
    slb_csv_columns species 1,15 | sed -n "s/^discere:sealifebase_species:$1,//p"
}

# Zeile der Art <speccode> in genus_report.tsv, ohne die Spalte mit dem Namen.
slb_genus_report_of() {
    awk -F '\t' -v key="$1" '$2 == key { print $1 "\t" $4 }' "$TEST_TMP/export/genus_report.tsv"
}

# Gattung und Familie der Art einig, auch wenn die Ordnung dieser Familie
# mehrdeutig ist: Die Gattung bleibt, ohne Eintrag im Bericht.
test_sealifebase_export_keeps_genus_that_matches_species_family() {
    run_genus_check_export
    assert_eq "discere:sealifebase_genus:1" "$(slb_genus_of 10)" "Abra alba"
    assert_eq "discere:sealifebase_genus:7" "$(slb_genus_of 29)" "Ambix certus"
    assert_eq "" "$(slb_genus_report_of 10)$(slb_genus_report_of 29)" "Bericht"
    assert_contains "$(slb_csv_columns species_scientific_names 2)" "Ambix certus"
}

# Liegt die Gattung in einem anderen Stamm oder einer anderen Klasse als die
# Familie der Art, bleibt die Gattung leer.
test_sealifebase_export_rejects_genus_from_other_phylum_or_class() {
    run_genus_check_export
    assert_eq "" "$(slb_genus_of 22)" "Gattya humilis"
    assert_eq "" "$(slb_genus_of 23)" "Murex brandaris"
    assert_eq "genus_rejected	Stamm: GenCode 4 Gattya (Ceramiaceae / Ceramiales / Florideophyceae / Rhodophyta), Art: Halopterididae / Leptothecata / Hydrozoa / Cnidaria" \
        "$(slb_genus_report_of 22)" "Bericht Stamm"
    assert_eq "genus_rejected	Klasse: GenCode 5 Murex (Muricidae / Neogastropoda / Gastropoda / Mollusca), Art: Semelidae / Cardiida / Bivalvia / Mollusca" \
        "$(slb_genus_report_of 23)" "Bericht Klasse"
}

# Heißt die Gattung des GenCode anders, als die Art ihre Gattung nennt, ist
# es eine andere Gattung: leer, auch bei gleicher Familie.
test_sealifebase_export_rejects_genus_with_other_name() {
    run_genus_check_export
    assert_eq "" "$(slb_genus_of 24)" "Stephanomia amphytridis"
    assert_eq "genus_rejected	Name: GenCode 6 Halistemma (Halopterididae / Leptothecata / Hydrozoa / Cnidaria), Art: Halopterididae / Leptothecata / Hydrozoa / Cnidaria" \
        "$(slb_genus_report_of 24)" "Bericht"
}

# Ist die Ordnung auf einer Seite unbekannt oder unter einem doppelten
# Ordnum nicht auflösbar, lässt sich nicht vergleichen: leer.
test_sealifebase_export_rejects_genus_when_order_is_unclear() {
    run_genus_check_export
    assert_eq "" "$(slb_genus_of 28)" "Abra orba"
    assert_eq "" "$(slb_genus_of 33)" "Abra mixta"
    assert_eq "genus_rejected	Ordnung unklar: GenCode 1 Abra (Semelidae / Cardiida / Bivalvia / Mollusca), Art: Orphanidae / ? / ? / ?" \
        "$(slb_genus_report_of 28)" "Bericht unbekannte Ordnung"
    assert_eq "genus_rejected	Ordnung unklar: GenCode 1 Abra (Semelidae / Cardiida / Bivalvia / Mollusca), Art: Mixtidae / ? / ? / ?" \
        "$(slb_genus_report_of 33)" "Bericht doppelter Ordnum"
}

# Unter einem doppelten Ordnum gilt für den Vergleich die Ordnung, die Name
# und ClassNum der Familie wählen: Weicht dann nur die Ordnung ab, bleibt die
# Gattung; zeigt die Kette eine andere Klasse, bleibt sie leer.
test_sealifebase_export_compares_genus_through_resolved_duplicate_order() {
    run_genus_check_export
    assert_eq "discere:sealifebase_genus:7" "$(slb_genus_of 25)" "Ambix dubius"
    assert_eq "genus_kept_order_differs	GenCode 7 Ambix (Ambigidae / Ostreida / Bivalvia / Mollusca), Art: Semelidae / Cardiida / Bivalvia / Mollusca" \
        "$(slb_genus_report_of 25)" "Bericht Ordnung"
    assert_eq "" "$(slb_genus_of 32)" "Ambix aranea"
    assert_eq "genus_rejected	Klasse: GenCode 7 Ambix (Ambigidae / Ostreida / Bivalvia / Mollusca), Art: Muricidae / Neogastropoda / Gastropoda / Mollusca" \
        "$(slb_genus_report_of 32)" "Bericht Klasse"
}

# Liegen beide Familien unter derselben Platzhalter-Klasse („Not assigned“),
# ist ihre echte Klasse unbekannt; gleich ist sie deshalb nicht: leer.
test_sealifebase_export_rejects_genus_when_class_is_placeholder() {
    run_genus_check_export
    assert_eq "" "$(slb_genus_of 31)" "Placo incertus"
    assert_eq "genus_rejected	Ordnung unklar: GenCode 9 Placo (Barridae / Not assigned / Not assigned / Mollusca), Art: Fooidae / Not assigned / Not assigned / Mollusca" \
        "$(slb_genus_report_of 31)" "Bericht"
}

# Weicht nur die Familie oder die Ordnung ab, Klasse und Stamm gleich, bleibt
# die Gattung; der Bericht nennt beide Ketten.
test_sealifebase_export_keeps_genus_when_only_family_or_order_differs() {
    run_genus_check_export
    assert_eq "discere:sealifebase_genus:2" "$(slb_genus_of 20)" "Tellina tenuis"
    assert_eq "discere:sealifebase_genus:3" "$(slb_genus_of 21)" "Venus verrucosa"
    assert_eq "genus_kept_family_differs	GenCode 2 Tellina (Tellinidae / Cardiida / Bivalvia / Mollusca), Art: Semelidae / Cardiida / Bivalvia / Mollusca" \
        "$(slb_genus_report_of 20)" "Bericht Familie"
    assert_eq "genus_kept_order_differs	GenCode 3 Venus (Veneridae / Venerida / Bivalvia / Mollusca), Art: Semelidae / Cardiida / Bivalvia / Mollusca" \
        "$(slb_genus_report_of 21)" "Bericht Ordnung"
    assert_contains "$(slb_csv_columns species_scientific_names 2)" "Venus verrucosa"
}

# Ohne GenCode gilt für die Gattung des Namens dieselbe Prüfung.
test_sealifebase_export_checks_genus_found_by_name() {
    run_genus_check_export
    assert_eq "discere:sealifebase_genus:8" "$(slb_genus_of 26)" "Solus novus"
    assert_eq "" "$(slb_genus_of 27)" "Abra rara"
    assert_eq "genus_by_name	GenCode 8" "$(slb_genus_report_of 26)" "Bericht passt"
    assert_eq "discere:sealifebase_genus:2" "$(slb_genus_of 30)" "Tellina nova"
    assert_eq "genus_kept_family_differs	über den Namen, GenCode 2 Tellina (Tellinidae / Cardiida / Bivalvia / Mollusca), Art: Semelidae / Cardiida / Bivalvia / Mollusca" \
        "$(slb_genus_report_of 30)" "Bericht Familie anders"
    assert_eq "genus_rejected	Stamm: über den Namen, GenCode 1 Abra (Semelidae / Cardiida / Bivalvia / Mollusca), Art: Ceramiaceae / Ceramiales / Florideophyceae / Rhodophyta" \
        "$(slb_genus_report_of 27)" "Bericht Stamm"
}

# Eine Art, deren Gattung verworfen wurde, behält den Namen, den die Quelle
# ihr gibt (Genus und Species), als bevorzugten Namen — nicht den mit dem
# Namen der verworfenen Gattung.
test_sealifebase_export_keeps_source_name_of_species_with_rejected_genus() {
    run_genus_check_export
    assert_eq "discere:sealifebase_species:22,Gattya humilis,gattya humilis,valid,1
discere:sealifebase_species:23,Murex brandaris,murex brandaris,valid,1
discere:sealifebase_species:24,Stephanomia amphytridis,stephanomia amphytridis,valid,1
discere:sealifebase_species:25,Ambix dubius,ambix dubius,valid,1
discere:sealifebase_species:27,Abra rara,abra rara,valid,1
discere:sealifebase_species:28,Abra orba,abra orba,valid,1" \
        "$(slb_csv_columns species_scientific_names 1-4,7 | grep -E 'species:(2[2-578]),')" \
        "bevorzugte Namen"
    assert_not_contains "$(cat "$TEST_TMP/export/species_scientific_names.csv")" "halistemma"
}

# Je Art höchstens eine Zeile, Arten mit passender Gattung über GenCode keine,
# sortiert nach Kategorie und Name.
test_sealifebase_export_reports_each_genus_check_once() {
    run_genus_check_export
    assert_eq "genus_by_name	26	Solus novus
genus_kept_family_differs	30	Tellina nova
genus_kept_family_differs	20	Tellina tenuis
genus_kept_order_differs	25	Ambix dubius
genus_kept_order_differs	21	Venus verrucosa
genus_rejected	33	Abra mixta
genus_rejected	28	Abra orba
genus_rejected	27	Abra rara
genus_rejected	32	Ambix aranea
genus_rejected	22	Gattya humilis
genus_rejected	23	Murex brandaris
genus_rejected	31	Placo incertus
genus_rejected	24	Stephanomia amphytridis" "$(cut -f 1-3 "$TEST_TMP/export/genus_report.tsv")" "Bericht"
}

# Unter einem doppelten Ordnum bekommt eine Familie die Ordnungszeile, deren
# Name und ClassNum sie selbst nennt; Entität wird nur die Zeile, an deren
# Familien Arten hängen. Desidae wählt Araneae, die ohne Arten nicht
# exportiert wird; Mixtidae nennt den Namen Ostreida, aber eine andere
# Klasse; unter Ordnum 8 hält keine Zeile Arten.
test_sealifebase_export_resolves_duplicate_order_code_by_name_and_class() {
    run_genus_check_export
    assert_eq "discere:sealifebase_order:7,Ostreida,discere:sealifebase_class:1" \
        "$(slb_csv_columns orders 1,4,6 | grep -E '_order:[78],')" "Ordnungen unter doppelten Codes"
    assert_eq "discere:sealifebase_family:11,
discere:sealifebase_family:12,
discere:sealifebase_family:13,
discere:sealifebase_family:7,discere:sealifebase_order:7" \
        "$(slb_csv_columns families 1,7 | grep -E '_family:(7|1[123]),')" "Ordnung je Familie"
}

# Hängt unter Desidae (11) die Art 34 Desis marina: Unter Ordnum 7 halten
# dann Ostreida und Araneae Arten.
add_species_under_second_duplicate_order() {
    local dir="$TEST_TMP/sealifebase"
    duckdb << SQL
CREATE TABLE species AS SELECT * FROM '$dir/species.parquet';
INSERT INTO species (SpecCode, Genus, Species, GenCode, FamCode) VALUES (34, 'Desis', 'marina', NULL, 11);
COPY species TO '$dir/species.parquet' (FORMAT parquet);
SQL
}

# Halten unter einem doppelten Ordnum mehrere Zeilen Arten, nennt der Code
# kein Taxon: Keine Zeile wird exportiert, keine Familie darunter bekommt
# eine Ordnung, und der Bericht nennt den Fall.
test_sealifebase_export_skips_duplicate_order_code_held_by_several_rows() {
    create_sealifebase_parquets
    write_genus_check_parquets
    add_species_under_second_duplicate_order
    run_sealifebase_export
    assert_status 0
    assert_eq "" "$(slb_csv_columns orders 1 | grep -E '_order:[78]$')" "Ordnungen unter doppelten Codes"
    assert_eq "discere:sealifebase_family:11,
discere:sealifebase_family:12,
discere:sealifebase_family:7," \
        "$(slb_csv_columns families 1,7 | grep -E '_family:(7|1[12]),')" "Ordnung je Familie"
    assert_eq "code_duplicate	Ordnum 7	Araneae	2 Zeilen; keine exportiert, mehrere Zeilen halten Arten
code_duplicate	Ordnum 7	Ostreida	2 Zeilen; keine exportiert, mehrere Zeilen halten Arten
family_order_rejected	11	Desidae	Ordnum 7 doppelt, Familie nennt Araneae (ClassNum 6): Ordnung Araneae nicht exportiert
family_order_rejected	12	Mixtidae	Ordnum 7 doppelt, Familie nennt ostreida (ClassNum 2): keine Ordnungszeile mit diesem Namen und dieser ClassNum
family_order_rejected	7	Ambigidae	Ordnum 7 doppelt, Familie nennt Ostreida (ClassNum 1): Ordnung Ostreida nicht exportiert" \
        "$(grep 'Ordnum 7' "$TEST_TMP/export/code_report.tsv")" "Bericht"
}

# Hängt unter Chromidae (13) die Art 35 Chromus vagus: Unter Ordnum 8 hält
# dann nur die Platzhalter-Zeile „Not assigned“ Arten.
add_species_under_placeholder_duplicate_order() {
    local dir="$TEST_TMP/sealifebase"
    duckdb << SQL
CREATE TABLE species AS SELECT * FROM '$dir/species.parquet';
INSERT INTO species (SpecCode, Genus, Species, GenCode, FamCode) VALUES (35, 'Chromus', 'vagus', NULL, 13);
COPY species TO '$dir/species.parquet' (FORMAT parquet);
SQL
}

# Ein Rang-Platzhalter trägt nie den Schlüssel eines doppelten Codes: Zwei
# gleichnamige Platzhalter verschiedener Klassen könnten ihn sonst tauschen,
# ohne dass ein Name sich ändert. Hält nur er Arten, wird keine Zeile
# exportiert.
test_sealifebase_export_never_gives_duplicate_order_code_to_placeholder() {
    create_sealifebase_parquets
    write_genus_check_parquets
    add_species_under_placeholder_duplicate_order
    run_sealifebase_export
    assert_status 0
    assert_eq "" "$(slb_csv_columns orders 1 | grep -E '_order:8$')" "Ordnung unter Ordnum 8"
    assert_eq "discere:sealifebase_family:13," "$(slb_csv_columns families 1,7 | grep '_family:13,')" "Chromidae"
    assert_eq "code_duplicate	Ordnum 8	Not assigned	2 Zeilen; keine exportiert, nur ein Platzhalter hält Arten
code_duplicate	Ordnum 8	Phymosomatoida	2 Zeilen; keine exportiert, nur ein Platzhalter hält Arten" \
        "$(grep 'Ordnum 8	' "$TEST_TMP/export/code_report.tsv")" "Bericht"
}

# Fügt unter Ordnum 7 die Familie 14 Ostreidae hinzu, die ihre Ordnung
# „ ostreida “ schreibt, in der Klasse der Zeile Ostreida.
add_family_naming_order_in_other_spelling() {
    local dir="$TEST_TMP/sealifebase"
    duckdb << SQL
CREATE TABLE families AS SELECT * FROM '$dir/families.parquet';
INSERT INTO families (FamCode, Family, Ordnum, "Order", ClassNum, Phylum) VALUES (14, 'Ostreidae', 7, ' ostreida ', 1, 'Mollusca');
COPY families TO '$dir/families.parquet' (FORMAT parquet);
SQL
}

# Den Namen der Ordnung vergleicht die Regel ohne Leerzeichen am Rand und
# ohne Groß- und Kleinschreibung.
test_sealifebase_export_matches_duplicate_order_name_ignoring_case_and_spaces() {
    create_sealifebase_parquets
    write_genus_check_parquets
    add_family_naming_order_in_other_spelling
    run_sealifebase_export
    assert_status 0
    assert_eq "discere:sealifebase_family:14,discere:sealifebase_order:7" \
        "$(slb_csv_columns families 1,7 | grep '_family:14,')" "Ostreidae"
}

# Ein doppelter GenCode nennt keine Gattung: Keine der Zeilen wird
# exportiert.
test_sealifebase_export_skips_duplicate_genus_code() {
    run_genus_check_export
    assert_not_contains "$(slb_csv_columns genera 1)" "discere:sealifebase_genus:10"
}

# Jede Klasse, Ordnung, Familie, Gattung und Art steht genau einmal im
# Export, auch unter doppelten Codes.
test_sealifebase_export_writes_each_entity_once() {
    local table
    run_genus_check_export
    for table in classes orders families genera species; do
        assert_eq "" "$(slb_csv_columns "$table" 1 | uniq -d)" "doppelte Zeilen in $table"
    done
    assert_eq "15" "$(slb_csv_columns species 1 | wc -l | tr -d ' ')" "Arten"
}

# Der Bericht nennt jede Zeile eines doppelten Codes mit ihrem Ausgang und
# jede Familie unter einem doppelten Ordnum mit ihrer Ordnung oder dem Grund,
# warum sie keine hat.
test_sealifebase_export_reports_duplicate_codes() {
    run_genus_check_export
    assert_eq "code_duplicate	GenCode 10	Dupla	2 Zeilen; keine exportiert, ohne Name zur Auswahl
code_duplicate	GenCode 10	Duplex	2 Zeilen; keine exportiert, ohne Name zur Auswahl
code_duplicate	Ordnum 7	Araneae	2 Zeilen; nicht exportiert, Schlüssel bei Ostreida
code_duplicate	Ordnum 7	Ostreida	2 Zeilen; Entität unter diesem Schlüssel (einzige Zeile mit Arten)
code_duplicate	Ordnum 8	Not assigned	2 Zeilen; keine exportiert, keine Zeile hält Arten
code_duplicate	Ordnum 8	Phymosomatoida	2 Zeilen; keine exportiert, keine Zeile hält Arten
family_order_rejected	11	Desidae	Ordnum 7 doppelt, Familie nennt Araneae (ClassNum 6): Ordnung Araneae nicht exportiert
family_order_rejected	12	Mixtidae	Ordnum 7 doppelt, Familie nennt ostreida (ClassNum 2): keine Ordnungszeile mit diesem Namen und dieser ClassNum
family_order_rejected	13	Chromidae	Ordnum 8 doppelt, Familie nennt Not assigned (ClassNum 5): Ordnung Not assigned nicht exportiert
family_order_resolved	7	Ambigidae	Ordnum 7 doppelt, Familie nennt Ostreida (ClassNum 1): Ordnung Ostreida" \
        "$(cat "$TEST_TMP/export/code_report.tsv")" "Bericht"
}

# Ersetzt die Taxonomie durch Familien, deren eigener Stamm (families.Phylum)
# und Stamm der Kette über ihren Ordnungscode sich unterscheiden:
#
#   Familie             nennt                     Ordnum zeigt auf
#   1  Priapulidae      Priapulida, Not assigned  1 Cocculiniformia (Mollusca);
#                       in Klasse 2               genau eine Zeile Not assigned
#                                                 in Klasse 2 (Priapulida)
#   2  Ceratiaceae      Dinophyta                 3 Peridiniales (Myzozoa)
#   3  Maccabeidae      Priapulida, Not assigned  1; zwei Zeilen Not assigned in
#                       in Klasse 4               Klasse 4
#   4  Psamminidae      Foraminifera, Not         1; keine Ordnung in Klasse 9
#                       assigned in Klasse 9
#   5  Phoronidae       Phoronida, Not assigned   1; genau eine Zeile Not
#                       in Klasse 7               assigned in Klasse 7, aber
#                                                 in Annelida
#   6  Trochosiraceae   Not Assigned (Plantae)    4 Not assigned (Not Assigned
#                                                 (Plantae))
#   7  Strombidiidae    Ciliophora                4
#   8  Cocculinidae     Mollusca                  1
#   10 Halicryptidae    Priapulida                2 Not assigned (Priapulida)
#
# Gattung 1 Priapulus gehört zu Priapulidae. Arten: 10 Priapulus caudatus
# (FamCode 1), 11 Priapulus spinulosus (FamCode 10), 12 Priapulus cocculinus
# (FamCode 8).
write_family_phylum_parquets() {
    local dir="$TEST_TMP/sealifebase"
    duckdb << SQL
COPY (SELECT ClassNum, Class, Phylum, NULL::VARCHAR AS CommonName FROM (VALUES
    (1, 'Gastropoda', 'Mollusca'), (2, 'Priapulomorpha', 'Priapulida'),
    (3, 'Dinophyceae', 'Myzozoa'), (4, 'Seticoronaria', 'Priapulida'),
    (5, 'Not assigned', 'Not Assigned (Plantae)'), (7, 'Polychaeta', 'Annelida'),
    (9, 'Monothalamea', 'Foraminifera')
) AS t(ClassNum, Class, Phylum)) TO '$dir/classes.parquet' (FORMAT parquet);

COPY (SELECT Ordnum, "Order", NULL::VARCHAR AS SisterOrder, ClassNum, NULL::VARCHAR AS CommonName,
             NULL::VARCHAR AS CommonName_German, NULL::VARCHAR AS CommonName_French,
             NULL::VARCHAR AS CommonName_Spanish
      FROM (VALUES (1, 'Cocculiniformia', 1), (2, 'Not assigned', 2), (3, 'Peridiniales', 3),
                   (4, 'Not assigned', 5), (5, 'Not assigned', 4), (6, 'Not assigned', 4),
                   (7, 'Not assigned', 7)
      ) AS t(Ordnum, "Order", ClassNum)) TO '$dir/orders.parquet' (FORMAT parquet);

COPY (SELECT FamCode, Family, NULL::VARCHAR AS Division, Ordnum, "Order", ClassNum, Phylum,
             NULL::VARCHAR AS CommonName, NULL::VARCHAR AS CommonName_German,
             NULL::VARCHAR AS CommonName_French, NULL::VARCHAR AS CommonName_Spanish
      FROM (VALUES (1, 'Priapulidae', 1, 'Not assigned', 2, 'Priapulida'),
                   (2, 'Ceratiaceae', 3, 'Peridiniales', 3, 'Dinophyta'),
                   (3, 'Maccabeidae', 1, 'Not assigned', 4, 'Priapulida'),
                   (4, 'Psamminidae', 1, 'Not assigned', 9, 'Foraminifera'),
                   (5, 'Phoronidae', 1, ' not ASSIGNED', 7, 'Phoronida'),
                   (6, 'Trochosiraceae', 4, 'Not assigned', 5, 'Not Assigned (Plantae)'),
                   (7, 'Strombidiidae', 4, 'Not assigned', 5, 'Ciliophora'),
                   (8, 'Cocculinidae', 1, 'Cocculiniformia', 1, 'Mollusca'),
                   (10, 'Halicryptidae', 2, 'Not assigned', 2, 'Priapulida')
      ) AS t(FamCode, Family, Ordnum, "Order", ClassNum, Phylum)) TO '$dir/families.parquet' (FORMAT parquet);

COPY (SELECT GenCode, GenName, NULL::VARCHAR AS Subfamily, FamCode, NULL::VARCHAR AS CommonName
      FROM (VALUES (1, 'Priapulus', 1)) AS t(GenCode, GenName, FamCode)) TO '$dir/genera.parquet' (FORMAT parquet);

COPY (SELECT SpecCode, Genus, Species, GenCode, FamCode, NULL::DOUBLE AS Length,
             NULL::INTEGER AS DepthRangeShallow, NULL::INTEGER AS DepthRangeComShallow,
             NULL::INTEGER AS DepthRangeDeep, NULL::INTEGER AS DepthRangeComDeep,
             NULL::VARCHAR AS DemersPelag, NULL::DOUBLE AS Vulnerability, NULL::VARCHAR AS Dangerous,
             NULL::VARCHAR AS Importance, NULL::FLOAT AS LongevityWild, NULL::VARCHAR AS BodyShapeI
      FROM (VALUES (10, 'Priapulus', 'caudatus', 1, 1), (11, 'Priapulus', 'spinulosus', 1, 10),
                   (12, 'Priapulus', 'cocculinus', 1, 8)
      ) AS t(SpecCode, Genus, Species, GenCode, FamCode)) TO '$dir/species.parquet' (FORMAT parquet);
SQL
}

run_family_phylum_export() {
    create_sealifebase_parquets
    write_family_phylum_parquets
    run_sealifebase_export
    assert_status 0
}

# Vorläufige Ordnungs-ID der Familie <famcode> in families.csv, leer ohne
# Ordnung.
slb_order_of() {
    slb_csv_columns families 1,7 | sed -n "s/^discere:sealifebase_family:$1,//p"
}

# Zeile der Familie <famcode> in family_phylum_report.tsv, ohne den Namen.
slb_family_phylum_report_of() {
    awk -F '\t' -v key="$1" '$2 == key { print $1 "\t" $4 }' "$TEST_TMP/export/family_phylum_report.tsv"
}

# Nennt die Familie einen anderen Namen desselben Stamms (laut
# plugins/sealifebase/data/family_phylum_equivalents.csv), bleibt die
# Ordnung ihres Codes, ohne Eintrag im Bericht.
test_sealifebase_export_keeps_order_when_family_names_equivalent_phylum() {
    run_family_phylum_export
    assert_eq "discere:sealifebase_order:3" "$(slb_order_of 2)" "Ceratiaceae"
    assert_eq "discere:sealifebase_order:1" "$(slb_order_of 8)" "Cocculinidae"
    assert_eq "" "$(slb_family_phylum_report_of 2)$(slb_family_phylum_report_of 8)" "Bericht"
}

# Zeigt der Ordnungscode in einen anderen Stamm, hängt die Familie unter der
# einzigen Ordnungszeile mit ihrem Ordnungsnamen und ihrer ClassNum, wenn
# deren Stamm passt. Die Identitäts-Stage erfährt den Wechsel aus
# parent_overrides.csv.
test_sealifebase_export_moves_family_to_order_of_its_own_phylum() {
    run_family_phylum_export
    assert_eq "discere:sealifebase_order:2" "$(slb_order_of 1)" "Priapulidae"
    assert_eq "family_phylum_resolved	Familie nennt Priapulida, Ordnum 1 zeigt auf Cocculiniformia / Gastropoda / Mollusca: Ordnung Not assigned / Priapulomorpha / Priapulida (Ordnum 2)" \
        "$(slb_family_phylum_report_of 1)" "Bericht"
    assert_eq "source,entity_type,external_id,parent_external_id
sealifebase,family,1,2" "$(cat "$TEST_TMP/export/parent_overrides.csv")" "parent_overrides.csv"
}

# Ohne genau eine passende Ordnungszeile — keine, mehrere, oder eine in einem
# anderen Stamm als dem der Familie — bekommt sie keine Ordnung.
test_sealifebase_export_drops_order_when_family_phylum_has_no_unique_order() {
    run_family_phylum_export
    assert_eq "" "$(slb_order_of 3)$(slb_order_of 4)$(slb_order_of 5)" "Maccabeidae, Psamminidae, Phoronidae"
    assert_eq "family_phylum_rejected	Familie nennt Priapulida, Ordnum 1 zeigt auf Cocculiniformia / Gastropoda / Mollusca: keine Ordnung, 2 Ordnungszeilen Not assigned mit ClassNum 4" \
        "$(slb_family_phylum_report_of 3)" "Bericht mehrere"
    assert_eq "family_phylum_rejected	Familie nennt Foraminifera, Ordnum 1 zeigt auf Cocculiniformia / Gastropoda / Mollusca: keine Ordnung, keine Ordnungszeile Not assigned mit ClassNum 9" \
        "$(slb_family_phylum_report_of 4)" "Bericht keine"
    assert_eq "family_phylum_rejected	Familie nennt Phoronida, Ordnum 1 zeigt auf Cocculiniformia / Gastropoda / Mollusca: keine Ordnung, Ordnung Not assigned / Polychaeta / Annelida (Ordnum 7) in anderem Stamm" \
        "$(slb_family_phylum_report_of 5)" "Bericht anderer Stamm"
    assert_not_contains "$(cat "$TEST_TMP/export/parent_overrides.csv")" "family,5,"
}

# Ein Platzhalter-Stamm auf einer Seite lässt sich nicht vergleichen: Die
# Ordnung bleibt, der Bericht nennt den Fall.
test_sealifebase_export_keeps_order_when_phylum_is_placeholder() {
    run_family_phylum_export
    assert_eq "discere:sealifebase_order:4" "$(slb_order_of 6)" "Trochosiraceae"
    assert_eq "discere:sealifebase_order:4" "$(slb_order_of 7)" "Strombidiidae"
    assert_eq "family_phylum_unclear	Familie nennt Not Assigned (Plantae), Ordnum 4 zeigt auf Not assigned / Not assigned / Not Assigned (Plantae): nicht vergleichbar, Ordnung bleibt" \
        "$(slb_family_phylum_report_of 6)" "Bericht Familie"
    assert_eq "family_phylum_unclear	Familie nennt Ciliophora, Ordnum 4 zeigt auf Not assigned / Not assigned / Not Assigned (Plantae): nicht vergleichbar, Ordnung bleibt" \
        "$(slb_family_phylum_report_of 7)" "Bericht Kette"
}

# Der Gattungsvergleich (#333) sieht die berichtigte Kette: Priapulus
# spinulosus (Familie in Priapulida) behält die Gattung aus Priapulidae, nur
# die Familie weicht ab; Priapulus cocculinus (Familie unter den Schnecken)
# verliert sie.
test_sealifebase_export_compares_genus_through_family_moved_by_phylum() {
    run_family_phylum_export
    assert_eq "discere:sealifebase_genus:1" "$(slb_genus_of 11)" "Priapulus spinulosus"
    assert_eq "genus_kept_family_differs	GenCode 1 Priapulus (Priapulidae / Not assigned / Priapulomorpha / Priapulida), Art: Halicryptidae / Not assigned / Priapulomorpha / Priapulida" \
        "$(slb_genus_report_of 11)" "Bericht behalten"
    assert_eq "" "$(slb_genus_of 12)" "Priapulus cocculinus"
    assert_eq "genus_rejected	Stamm: GenCode 1 Priapulus (Priapulidae / Not assigned / Priapulomorpha / Priapulida), Art: Cocculinidae / Cocculiniformia / Gastropoda / Mollusca" \
        "$(slb_genus_report_of 12)" "Bericht verworfen"
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

# Ersetzt synonyms.parquet durch Synonyme von Abra alba (10) und Abra tenuis
# (11) auf verschiedenen Ebenen:
#   abra prima    ambiguous synonym bei 10 (Species) und 11 (Other)
#   abra secunda  Synonym bei 11 auf Species und Other — dieselbe Art
#   abra tertia   Synonym bei 10 und beim Platzhalter 14, der keine Art ist
#   abra quarta   falsch angewandt bei 10, Synonym bei 11
#   abra quinta   bei 11 nur als Varietät (kein Binom), Synonym bei 10
write_sealifebase_synonyms_across_levels() {
    duckdb << SQL
COPY (
    SELECT SpecCode, SynGenus, SynSpecies, 1 AS SynonymsRef, TaxonLevel, Status,
           NULL::VARCHAR AS Synonymy, NULL::VARCHAR AS Combination, 0 AS Misspelling
    FROM (VALUES
        (10, 'Abra', 'prima',          'Species', 'ambiguous synonym'),
        (11, 'Abra', 'prima',          'Other',   'ambiguous synonym'),
        (11, 'Abra', 'secunda',        'Species', 'synonym'),
        (11, 'Abra', 'secunda',        'Other',   'synonym'),
        (10, 'Abra', 'tertia',         'Species', 'synonym'),
        (14, 'Abra', 'tertia',         'Species', 'synonym'),
        (10, 'Abra', 'quarta',         'Species', 'misapplied name'),
        (11, 'Abra', 'quarta',         'Species', 'synonym'),
        (10, 'Abra', 'quinta',         'Species', 'synonym'),
        (11, 'Abra', 'quinta var. x',  'Variety', 'synonym')
    ) AS t(SpecCode, SynGenus, SynSpecies, TaxonLevel, Status)
) TO '$TEST_TMP/sealifebase/synonyms.parquet' (FORMAT parquet);
SQL
}

# Ein Name, den die Quelle als Synonym zweier Arten führt, ist mehrdeutig,
# auch wenn eine der Zeilen auf einer anderen Ebene als Species steht und
# deshalb nicht in species_scientific_names kommt. Dieselbe Art auf zwei
# Ebenen, ein Platzhalter, ein falsch angewandter Name und ein Name, der kein
# Binom ist, machen keinen Namen mehrdeutig.
test_sealifebase_export_lists_names_that_are_synonyms_of_several_species() {
    create_sealifebase_parquets
    write_sealifebase_synonyms_across_levels
    run_sealifebase_export
    assert_status 0
    assert_eq "abra prima,sealifebase,2" "$(slb_csv_columns ambiguous_scientific_names 1-3)" "mehrdeutige Namen"
    assert_eq "discere:sealifebase_species:10,abra prima" \
        "$(slb_csv_columns species_scientific_names 1,3 | grep 'abra prima')" "Name nur auf der Ebene Species"
}
