-- =============================================================================
-- SeaLifeBase Export — eine einzige DuckDB-Session
--
-- SeaLifeBase hat dieselbe Tabellenstruktur wie FishBase.
-- Spaltennamen sind identisch — nur source = 'sealifebase'.
--
-- SpecCodes sind datenbankspezifisch: FishBase- und SeaLifeBase-SpecCodes
-- sind unabhängige Zähler und können sich überschneiden. Das ist kein Problem
-- da external_source sie eindeutig trennt.
--
-- fieldguide_pic ist in SLB optional — wird übersprungen wenn nicht vorhanden.
-- =============================================================================

CREATE OR REPLACE MACRO discere_uuid(source, entity, external_id) AS
    'discere:' || source || '_' || entity || ':' || CAST(external_id AS VARCHAR);

-- ---------------------------------------------------------------------------
-- Classes
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_classes AS
SELECT
    discere_uuid('sealifebase', 'class', classnum)  AS id,
    CAST(classnum AS VARCHAR)                       AS external_id,
    'sealifebase'                                   AS external_source,
    class                                           AS name,
    commonName                                      AS common_name,
    phylum                                          AS super_class  -- SLB hat kein superclass; Phylum als Ersatz
FROM read_parquet('${SLB_DIR}/classes.parquet');

COPY t_classes TO '${EXPORT_DIR}/classes.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Orders (FK → classes)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_orders AS
SELECT
    discere_uuid('sealifebase', 'order', o.ordnum)  AS id,
    CAST(o.ordnum AS VARCHAR)                       AS external_id,
    'sealifebase'                                   AS external_source,
    o."order"                                       AS name,
    o.commonName                                    AS common_name_en,
    o.commonName_German                             AS common_name_de,
    o.commonName_French                             AS common_name_fr,
    o.commonName_Spanish                            AS common_name_es,
    c.id                                            AS class
FROM read_parquet('${SLB_DIR}/orders.parquet') o
LEFT JOIN t_classes c ON c.external_id = CAST(o.classNum AS VARCHAR);

COPY t_orders TO '${EXPORT_DIR}/orders.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Families (FK → orders)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_families AS
SELECT
    discere_uuid('sealifebase', 'family', f.famcode)  AS id,
    CAST(f.famcode AS VARCHAR)                        AS external_id,
    'sealifebase'                                     AS external_source,
    f.family                                          AS name,
    f.commonName                                      AS common_name_en,
    f.commonName_German                               AS common_name_de,
    f.commonName_French                               AS common_name_fr,
    f.commonName_Spanish                              AS common_name_es,
    o.id                                              AS "order"
FROM read_parquet('${SLB_DIR}/families.parquet') f
LEFT JOIN t_orders o ON o.external_id = CAST(f.ordnum AS VARCHAR);

COPY t_families TO '${EXPORT_DIR}/families.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Genera (FK → families)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_genera AS
SELECT
    discere_uuid('sealifebase', 'genus', g.gencode)  AS id,
    CAST(g.gencode AS VARCHAR)                       AS external_id,
    'sealifebase'                                    AS external_source,
    g.GenName                                        AS name,
    g.Subfamily                                      AS subfamily,
    g.CommonName                                     AS common_name,
    f.id                                             AS family
FROM read_parquet('${SLB_DIR}/genera.parquet') g
LEFT JOIN t_families f ON f.external_id = CAST(g.famcode AS VARCHAR);

COPY t_genera TO '${EXPORT_DIR}/genera.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Species (FK → genera)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_species AS
SELECT
    discere_uuid('sealifebase', 'species', s.speccode)                                           AS id,
    CAST(s.speccode AS VARCHAR)                                                                  AS external_id,
    'sealifebase'                                                                                AS external_source,
    MAX(s.species)                                                                               AS name,
    STRING_AGG(DISTINCT CASE WHEN c.language = 'German'  THEN c.comname END, ';')               AS common_name_de,
    STRING_AGG(DISTINCT CASE WHEN c.language = 'English' THEN c.comname END, ';')               AS common_name_en,
    STRING_AGG(DISTINCT CASE WHEN c.language = 'French'  THEN c.comname END, ';')               AS common_name_fr,
    STRING_AGG(DISTINCT CASE WHEN c.language = 'Spanish' THEN c.comname END, ';')               AS common_name_es,
    MAX(s.Length)                                                                                AS max_length_cm,
    MAX(g.id)                                                                                    AS genus,
    'active'                                                                                     AS status,
    NULL                                                                                         AS deprecated_at
FROM read_parquet('${SLB_DIR}/species.parquet') s
LEFT JOIN read_parquet('${SLB_DIR}/comnames.parquet') c
    ON CAST(s.speccode AS VARCHAR) = CAST(c.speccode AS VARCHAR)
    AND c.language IN ('German', 'English', 'French', 'Spanish')
LEFT JOIN t_genera g ON g.external_id = CAST(s.gencode AS VARCHAR)
GROUP BY s.speccode
ORDER BY s.speccode;

COPY t_species TO '${EXPORT_DIR}/species.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Pictures (picturesmain)
-- ---------------------------------------------------------------------------
COPY (
    SELECT
        discere_uuid('sealifebase', 'pic', CAST(p.speccode AS VARCHAR) || ':' || p.picname)  AS id,
        sp.id                                                                                  AS species,
        p.picname                                                                              AS picname,
        p.picturetype                                                                          AS picturetype,
        p.lifestage                                                                            AS lifestage,
        p.authname                                                                             AS author,
        p.copyright                                                                            AS copyright,
        CONCAT('https://sealifebase.net.br/images/species/', p.picname)                       AS url,
        'sealifebase'                                                                          AS origin
    FROM read_parquet('${SLB_DIR}/picturesmain.parquet') p
    LEFT JOIN t_species sp ON sp.external_id = CAST(p.speccode AS VARCHAR)
    WHERE p.picturetype IN (
        'photo', 'underwater photo', 'occurrence', 'aquarium photo',
        'public aquarium', 'color drawing', 'b/w drawing',
        'b/w drawing with inserts', 'Randall''s tank photos'
    )
)
TO '${EXPORT_DIR}/pictures.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Pictures (fieldguide_pic) — optional, nicht alle SLB-Versionen enthalten diese Tabelle
-- Wird in import.sh separat behandelt.
-- ---------------------------------------------------------------------------
