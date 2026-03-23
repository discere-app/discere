-- =============================================================================
-- FishBase Export — eine einzige DuckDB-Session
--
-- Alle IDs werden als VARCHAR (TEXT) behandelt — konsistent mit SQLite schema.
-- Parents werden zuerst geladen; Children joinen auf diese für FK-Auflösung.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Classes
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_classes AS
SELECT
    uuid()                      AS id,
    CAST(classnum AS VARCHAR)   AS external_id,
    'fishbase'                  AS external_source,
    class                       AS name,
    commonName                  AS common_name,
    superclass                  AS super_class
FROM read_parquet('${FISHBASE_DIR}/classes.parquet');

COPY t_classes TO '${EXPORT_DIR}/classes.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Orders (FK → classes)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_orders AS
SELECT
    uuid()                      AS id,
    CAST(o.ordnum AS VARCHAR)   AS external_id,
    'fishbase'                  AS external_source,
    o."order"                   AS name,
    o.commonName                AS common_name_en,
    o.commonName_German         AS common_name_de,
    o.commonName_French         AS common_name_fr,
    o.commonName_Spanish        AS common_name_es,
    c.id                        AS class
FROM read_parquet('${FISHBASE_DIR}/orders.parquet') o
LEFT JOIN t_classes c ON c.external_id = CAST(o.classNum AS VARCHAR);

COPY t_orders TO '${EXPORT_DIR}/orders.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Families (FK → orders)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_families AS
SELECT
    uuid()                      AS id,
    CAST(f.famcode AS VARCHAR)  AS external_id,
    'fishbase'                  AS external_source,
    f.family                    AS name,
    f.commonName                AS common_name_en,
    f.commonName_German         AS common_name_de,
    f.commonName_French         AS common_name_fr,
    f.commonName_Spanish        AS common_name_es,
    o.id                        AS "order"
FROM read_parquet('${FISHBASE_DIR}/families.parquet') f
LEFT JOIN t_orders o ON o.external_id = CAST(f.ordnum AS VARCHAR);

COPY t_families TO '${EXPORT_DIR}/families.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Genera (FK → families)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_genera AS
SELECT
    uuid()                      AS id,
    CAST(g.gencode AS VARCHAR)  AS external_id,
    'fishbase'                  AS external_source,
    g.genname                   AS name,
    g.subfamily                 AS subfamily,
    g.gencomname                AS common_name,
    f.id                        AS family
FROM read_parquet('${FISHBASE_DIR}/genera.parquet') g
LEFT JOIN t_families f ON f.external_id = CAST(g.famcode AS VARCHAR);

COPY t_genera TO '${EXPORT_DIR}/genera.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Species (FK → genera)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_species AS
SELECT
    uuid()                                                                         AS id,
    CAST(s.speccode AS VARCHAR)                                                    AS external_id,
    'fishbase'                                                                     AS external_source,
    MAX(s.species)                                                                 AS name,
    STRING_AGG(DISTINCT CASE WHEN c.language = 'German'  THEN c.comname END, ';') AS common_name_de,
    STRING_AGG(DISTINCT CASE WHEN c.language = 'English' THEN c.comname END, ';') AS common_name_en,
    STRING_AGG(DISTINCT CASE WHEN c.language = 'French'  THEN c.comname END, ';') AS common_name_fr,
    STRING_AGG(DISTINCT CASE WHEN c.language = 'Spanish' THEN c.comname END, ';') AS common_name_es,
    MAX(s.commonlength)                                                            AS common_length,
    MAX(s.weight)                                                                  AS common_weight,
    g.id                                                                           AS genus
FROM read_parquet('${FISHBASE_DIR}/species.parquet') s
LEFT JOIN read_parquet('${FISHBASE_DIR}/comnames.parquet') c
    ON CAST(s.speccode AS VARCHAR) = CAST(c.speccode AS VARCHAR)
    AND c.language IN ('German', 'English', 'French', 'Spanish')
LEFT JOIN t_genera g ON g.external_id = CAST(s.gencode AS VARCHAR)
GROUP BY s.speccode, g.id
ORDER BY s.speccode;

COPY t_species TO '${EXPORT_DIR}/species.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Pictures (FK → species)
-- ---------------------------------------------------------------------------
COPY (
    SELECT
        uuid()                                                         AS id,
        sp.id                                                          AS species,
        p.picname                                                      AS picname,
        p.picturetype                                                  AS picturetype,
        p.lifestage                                                    AS lifestage,
        p.authname                                                     AS author,
        p.copyright                                                    AS copyright,
        CONCAT('https://fishbase.net.br/images/species/', p.picname)  AS url,
        'fishbase'                                                     AS origin
    FROM read_parquet('${FISHBASE_DIR}/picturesmain.parquet') p
    LEFT JOIN t_species sp ON sp.external_id = CAST(p.speccode AS VARCHAR)
    WHERE p.picturetype IN (
        'photo', 'underwater photo', 'occurrence', 'aquarium photo',
        'public aquarium', 'color drawing', 'b/w drawing',
        'b/w drawing with inserts', 'Randall''s tank photos'
    )
    UNION ALL
    SELECT
        uuid()                                                         AS id,
        sp.id                                                          AS species,
        fg.picname                                                     AS picname,
        'field guide'                                                  AS picturetype,
        'unsexed'                                                      AS lifestage,
        NULL                                                           AS author,
        NULL                                                           AS copyright,
        CONCAT('https://fishbase.net.br/images/species/', fg.picname) AS url,
        'fishbase'                                                     AS origin
    FROM read_parquet('${FISHBASE_DIR}/fieldguide_pic.parquet') fg
    LEFT JOIN t_species sp ON sp.external_id = CAST(fg.speccode AS VARCHAR)
)
TO '${EXPORT_DIR}/pictures.csv' (FORMAT csv, HEADER true);
