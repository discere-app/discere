-- =============================================================================
-- FishBase Export — eine einzige DuckDB-Session
--
-- Alle IDs werden als VARCHAR (TEXT) behandelt — konsistent mit SQLite schema.
-- Parents werden zuerst geladen; Children joinen auf diese für FK-Auflösung.
--
-- UUIDs werden deterministisch über die zentrale Funktion discere_uuid() erzeugt:
--   discere_uuid('fishbase', 'species', 12345)
--   → stable_uuid('discere:fishbase_species:12345')
--
-- Format: discere:<source>_<entity>:<external_id>
-- Namespace-Beispiele:
--   discere:fishbase_class:<id>
--   discere:fishbase_order:<id>
--   discere:fishbase_family:<id>
--   discere:fishbase_genus:<id>
--   discere:fishbase_species:<id>
--   discere:fishbase_pic:<speccode>:<picname>
--   discere:fishbase_fieldguide:<speccode>:<picname>
-- =============================================================================

-- Zentraler ID-Generator für alle Plugins.
-- Gibt einen deterministischen, lesbaren String zurück.
-- Format: discere:<source>_<entity>:<external_id>
-- Plugins dürfen keine IDs selbst konstruieren — nur diese Funktion verwenden.
CREATE OR REPLACE MACRO discere_uuid(source, entity, external_id) AS
    'discere:' || source || '_' || entity || ':' || CAST(external_id AS VARCHAR);

-- ---------------------------------------------------------------------------
-- Classes
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_classes AS
SELECT
    discere_uuid('fishbase', 'class', classnum)  AS id,
    CAST(classnum AS VARCHAR)                    AS external_id,
    'fishbase'                                   AS external_source,
    class                                        AS name,
    BodyShapeI                                   AS body_shape,
    superclass                                   AS super_class
FROM read_parquet('${FISHBASE_DIR}/classes.parquet');

COPY t_classes TO '${EXPORT_DIR}/classes.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Orders (FK → classes)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_orders AS
SELECT
    discere_uuid('fishbase', 'order', o.ordnum)  AS id,
    CAST(o.ordnum AS VARCHAR)                    AS external_id,
    'fishbase'                                   AS external_source,
    o."order"                                    AS name,
    o.SisterOrder                                AS sister_order,
    c.id                                         AS class
FROM read_parquet('${FISHBASE_DIR}/orders.parquet') o
LEFT JOIN t_classes c ON c.external_id = CAST(o.classNum AS VARCHAR);

COPY t_orders TO '${EXPORT_DIR}/orders.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Families (FK → orders)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_families AS
SELECT
    discere_uuid('fishbase', 'family', f.famcode)  AS id,
    CAST(f.famcode AS VARCHAR)                     AS external_id,
    'fishbase'                                     AS external_source,
    f.family                                       AS name,
    f.BodyShapeI                                   AS body_shape,
    f.Division                                     AS division,
    o.id                                           AS "order"
FROM read_parquet('${FISHBASE_DIR}/families.parquet') f
LEFT JOIN t_orders o ON o.external_id = CAST(f.ordnum AS VARCHAR);

COPY t_families TO '${EXPORT_DIR}/families.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Genera (FK → families)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_genera AS
SELECT
    discere_uuid('fishbase', 'genus', g.gencode)  AS id,
    CAST(g.gencode AS VARCHAR)                    AS external_id,
    'fishbase'                                    AS external_source,
    g.genname                                     AS name,
    g.subfamily                                   AS subfamily,
    g.BodyShapeI                                  AS body_shape,
    f.id                                          AS family
FROM read_parquet('${FISHBASE_DIR}/genera.parquet') g
LEFT JOIN t_families f ON f.external_id = CAST(g.famcode AS VARCHAR);

COPY t_genera TO '${EXPORT_DIR}/genera.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Ecology (für Habitat-Verdichtung, key = SpecCode)
-- Mehrere Stock-/Ecology-Zeilen pro Species werden auf einen Habitat-String
-- verdichtet. Falls keine Ecology-Zeile vorliegt, fällt species.DemersPelag
-- später als grobes Habitat-Label zurück.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_ecology AS
SELECT
    CAST(e.SpecCode AS VARCHAR) AS external_id,
    MAX(e.FoodTroph)            AS food_troph,
    CASE
        -- FishBase v25.04 no longer exposes a generic FreshWater flag here.
        -- Stream / Lakes still exist and are the safest freshwater proxies.
        -- FishBase v25.04 uses -1/0 in several ecology flags.
        WHEN MAX(CASE WHEN COALESCE(e.Stream, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'freshwater stream'
        WHEN MAX(CASE WHEN COALESCE(e.Lakes, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'freshwater lake'
        WHEN MAX(CASE WHEN COALESCE(e.Mangroves, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'mangroves'
        WHEN MAX(CASE WHEN COALESCE(e.Estuaries, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'estuary'
        WHEN MAX(CASE WHEN COALESCE(e.SeaGrassBeds, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'seagrass beds'
        WHEN MAX(CASE WHEN COALESCE(e.CoralReefs, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'coral reef'
        WHEN MAX(CASE WHEN COALESCE(e.Lagoons, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'lagoon'
        WHEN MAX(CASE WHEN COALESCE(e.Caves, 0) <> 0 THEN 1 ELSE 0 END) = 1
          OR MAX(CASE WHEN COALESCE(e.Cave, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'cave'
        WHEN MAX(CASE WHEN COALESCE(e.Oceanic, 0) <> 0 THEN 1 ELSE 0 END) = 1
          AND MAX(CASE WHEN COALESCE(e.Epipelagic, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'open ocean (epipelagic)'
        WHEN MAX(CASE WHEN COALESCE(e.Oceanic, 0) <> 0 THEN 1 ELSE 0 END) = 1
          AND MAX(CASE WHEN COALESCE(e.Mesopelagic, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'open ocean (mesopelagic)'
        WHEN MAX(CASE WHEN COALESCE(e.Oceanic, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'open ocean'
        WHEN MAX(CASE WHEN COALESCE(e.HardBottom, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'hard bottom'
        WHEN MAX(CASE WHEN COALESCE(e.SoftBottom, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'soft bottom'
        WHEN MAX(CASE WHEN COALESCE(e.Demersal, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'demersal'
        WHEN MAX(CASE WHEN COALESCE(e.Pelagic, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'pelagic'
        WHEN MAX(CASE WHEN COALESCE(e.Benthic, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'benthic'
        WHEN MAX(CASE WHEN COALESCE(e.LittoralZone, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'littoral'
        WHEN MAX(CASE WHEN COALESCE(e.Neritic, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'neritic'
        ELSE NULL
    END AS habitat
FROM read_parquet('${FISHBASE_DIR}/ecology.parquet') e
GROUP BY e.SpecCode;

-- ---------------------------------------------------------------------------
-- Species (FK → genera)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_species AS
SELECT
    discere_uuid('fishbase', 'species', s.speccode)                                              AS id,
    CAST(s.speccode AS VARCHAR)                                                                  AS external_id,
    'fishbase'                                                                                   AS external_source,
    s.species                                                                                    AS name,
    s.Length                                                                                     AS max_length_cm,
    COALESCE(s.DepthRangeShallow, s.DepthRangeComShallow)                                        AS depth_min_m,
    COALESCE(s.DepthRangeDeep, s.DepthRangeComDeep)                                              AS depth_max_m,
    COALESCE(e.habitat, NULLIF(TRIM(s.DemersPelag), ''))                                         AS habitat,
    s.Vulnerability                                                                              AS vulnerability,
    NULLIF(TRIM(s.Dangerous), '')                                                                AS dangerous_to_humans,
    NULLIF(TRIM(s.Importance), '')                                                               AS fisheries_importance,
    s.LongevityWild                                                                              AS longevity_years,
    NULLIF(TRIM(s.BodyShapeI), '')                                                               AS body_shape,
    e.food_troph                                                                                 AS trophic_level_food,
    g.id                                                                                         AS genus,
    'active'                                                                                     AS status,
    NULL                                                                                         AS deprecated_at
FROM read_parquet('${FISHBASE_DIR}/species.parquet') s
LEFT JOIN t_ecology e ON e.external_id = CAST(s.speccode AS VARCHAR)
LEFT JOIN t_genera g ON g.external_id = CAST(s.gencode AS VARCHAR)
ORDER BY s.speccode;

COPY t_species TO '${EXPORT_DIR}/species.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Common Names
-- Trivialnamen für alle Entitäten (Species + Taxonomie).
-- Für Species: aus comnames.parquet mit vollem Ranking-Metadaten.
-- Für Taxonomie: aus den Einzelspalten der jeweiligen Tabellen.
--
-- Filterregeln:
--   - Nur Sprachen: German, English, French, Spanish
--   - NameType-Filter: historische/veraltete Typen werden ausgeschlossen
--   - C_Code 9999 (global/FAO) → country = NULL
--   - 'vernacular' (lowercase) wird zu 'Vernacular' normalisiert
-- ---------------------------------------------------------------------------
COPY (
    -- Species-Namen aus comnames.parquet
    SELECT
        discere_uuid('fishbase', 'species', CAST(c.speccode AS VARCHAR)) AS entity_id,
        'species'                                                         AS entity_type,
        CASE c.language
            WHEN 'German'  THEN 'de'
            WHEN 'English' THEN 'en'
            WHEN 'French'  THEN 'fr'
            WHEN 'Spanish' THEN 'es'
        END                                                               AS language,
        CASE WHEN CAST(c.c_code AS VARCHAR) = '9999' THEN NULL
             ELSE LPAD(CAST(c.c_code AS VARCHAR), 3, '0')
        END                                                               AS country,
        TRIM(c.comname)                                                   AS name,
        'fishbase'                                                        AS source,
        c.rank                                                            AS rank,
        c.preferredname                                                   AS is_preferred,
        CASE LOWER(TRIM(c.nametype))
            WHEN 'vernacular' THEN 'Vernacular'
            ELSE TRIM(c.nametype)
        END                                                               AS name_type
    FROM read_parquet('${FISHBASE_DIR}/comnames.parquet') c
    WHERE c.language IN ('German', 'English', 'French', 'Spanish')
      AND TRIM(c.comname) <> ''
      AND TRIM(c.nametype) NOT IN (
          'FAO old', 'FAO Old', 'AFS old', 'FAO alt',
          'FAO cat', 'FAO Cat', 'FAO syn', 'FAO split'
      )

    UNION ALL

    -- Order-Namen (je eine Zeile pro Sprache)
    SELECT discere_uuid('fishbase', 'order', o.ordnum), 'order', 'en', NULL,
           TRIM(o.commonName), 'fishbase', NULL, 1, NULL
    FROM read_parquet('${FISHBASE_DIR}/orders.parquet') o
    WHERE NULLIF(TRIM(o.commonName), '') IS NOT NULL

    UNION ALL

    SELECT discere_uuid('fishbase', 'order', o.ordnum), 'order', 'de', NULL,
           TRIM(o.commonName_German), 'fishbase', NULL, 1, NULL
    FROM read_parquet('${FISHBASE_DIR}/orders.parquet') o
    WHERE NULLIF(TRIM(o.commonName_German), '') IS NOT NULL

    UNION ALL

    SELECT discere_uuid('fishbase', 'order', o.ordnum), 'order', 'fr', NULL,
           TRIM(o.commonName_French), 'fishbase', NULL, 1, NULL
    FROM read_parquet('${FISHBASE_DIR}/orders.parquet') o
    WHERE NULLIF(TRIM(o.commonName_French), '') IS NOT NULL

    UNION ALL

    SELECT discere_uuid('fishbase', 'order', o.ordnum), 'order', 'es', NULL,
           TRIM(o.commonName_Spanish), 'fishbase', NULL, 1, NULL
    FROM read_parquet('${FISHBASE_DIR}/orders.parquet') o
    WHERE NULLIF(TRIM(o.commonName_Spanish), '') IS NOT NULL

    UNION ALL

    -- Family-Namen
    SELECT discere_uuid('fishbase', 'family', f.famcode), 'family', 'en', NULL,
           TRIM(f.commonName), 'fishbase', NULL, 1, NULL
    FROM read_parquet('${FISHBASE_DIR}/families.parquet') f
    WHERE NULLIF(TRIM(f.commonName), '') IS NOT NULL

    UNION ALL

    SELECT discere_uuid('fishbase', 'family', f.famcode), 'family', 'de', NULL,
           TRIM(f.commonName_German), 'fishbase', NULL, 1, NULL
    FROM read_parquet('${FISHBASE_DIR}/families.parquet') f
    WHERE NULLIF(TRIM(f.commonName_German), '') IS NOT NULL

    UNION ALL

    SELECT discere_uuid('fishbase', 'family', f.famcode), 'family', 'fr', NULL,
           TRIM(f.commonName_French), 'fishbase', NULL, 1, NULL
    FROM read_parquet('${FISHBASE_DIR}/families.parquet') f
    WHERE NULLIF(TRIM(f.commonName_French), '') IS NOT NULL

    UNION ALL

    SELECT discere_uuid('fishbase', 'family', f.famcode), 'family', 'es', NULL,
           TRIM(f.commonName_Spanish), 'fishbase', NULL, 1, NULL
    FROM read_parquet('${FISHBASE_DIR}/families.parquet') f
    WHERE NULLIF(TRIM(f.commonName_Spanish), '') IS NOT NULL

    UNION ALL

    -- Genera-Namen (nur Englisch, kein Sprachfeld in FishBase)
    SELECT discere_uuid('fishbase', 'genus', g.gencode), 'genus', 'en', NULL,
           TRIM(g.gencomname), 'fishbase', NULL, 1, NULL
    FROM read_parquet('${FISHBASE_DIR}/genera.parquet') g
    WHERE NULLIF(TRIM(g.gencomname), '') IS NOT NULL

    UNION ALL

    -- Class-Namen (nur Englisch)
    SELECT discere_uuid('fishbase', 'class', c.classnum), 'class', 'en', NULL,
           TRIM(c.commonName), 'fishbase', NULL, 1, NULL
    FROM read_parquet('${FISHBASE_DIR}/classes.parquet') c
    WHERE NULLIF(TRIM(c.commonName), '') IS NOT NULL

    ORDER BY entity_type, entity_id, language, country, rank, is_preferred DESC
)
TO '${EXPORT_DIR}/common_names.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Taxonomy Traits (Species-Habitat-Tags)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_taxonomy_traits AS
SELECT DISTINCT
    discere_uuid('fishbase', 'species', CAST(e.SpecCode AS VARCHAR)) AS entity_id,
    'species'                                                        AS entity_type,
    e.trait_key                                                      AS trait_key,
    CAST(NULL AS VARCHAR)                                            AS trait_value_text,
    CAST(NULL AS DOUBLE)                                             AS trait_value_num,
    1                                                                AS trait_value_bool,
    'fishbase'                                                       AS source
FROM (
    SELECT SpecCode, 'freshwater_stream_association' AS trait_key
    FROM read_parquet('${FISHBASE_DIR}/ecology.parquet')
    WHERE COALESCE(Stream, 0) <> 0

    UNION ALL

    SELECT SpecCode, 'lake_association' AS trait_key
    FROM read_parquet('${FISHBASE_DIR}/ecology.parquet')
    WHERE COALESCE(Lakes, 0) <> 0

    UNION ALL

    SELECT SpecCode, 'mangrove_association' AS trait_key
    FROM read_parquet('${FISHBASE_DIR}/ecology.parquet')
    WHERE COALESCE(Mangroves, 0) <> 0

    UNION ALL

    SELECT SpecCode, 'reef_association' AS trait_key
    FROM read_parquet('${FISHBASE_DIR}/ecology.parquet')
    WHERE COALESCE(CoralReefs, 0) <> 0

    UNION ALL

    SELECT SpecCode, 'seagrass_association' AS trait_key
    FROM read_parquet('${FISHBASE_DIR}/ecology.parquet')
    WHERE COALESCE(SeaGrassBeds, 0) <> 0
) e;

COPY t_taxonomy_traits TO '${EXPORT_DIR}/taxonomy_traits.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Taxonomy Distribution Regions (country / countrysub)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_taxonomy_distribution_regions AS
SELECT DISTINCT
    discere_uuid('fishbase', 'species', CAST(c.SpecCode AS VARCHAR)) AS entity_id,
    'species'                                                        AS entity_type,
    'fishbase'                                                       AS source,
    'country'                                                        AS region_scope,
    CAST(c.C_Code AS VARCHAR)                                        AS region_key,
    CAST(c.C_Code AS VARCHAR)                                        AS region_label,
    NULLIF(TRIM(c.CurrentPresence), '')                              AS presence_status,
    NULLIF(TRIM(c.Status), '')                                       AS establishment_status,
    c.Threatened                                                     AS threatened_flag,
    NULLIF(TRIM(c.Abundance), '')                                    AS abundance,
    NULLIF(TRIM(c.Importance), '')                                   AS importance,
    NULLIF(TRIM(c.Comments), '')                                     AS comment
FROM read_parquet('${FISHBASE_DIR}/country.parquet') c
WHERE c.SpecCode IS NOT NULL
  AND NULLIF(TRIM(CAST(c.C_Code AS VARCHAR)), '') IS NOT NULL

UNION ALL

SELECT DISTINCT
    discere_uuid('fishbase', 'species', CAST(cs.SpecCode AS VARCHAR))  AS entity_id,
    'species'                                                          AS entity_type,
    'fishbase'                                                         AS source,
    'subregion'                                                        AS region_scope,
    CAST(cs.C_Code AS VARCHAR) || ':' || CAST(cs.CSub_Code AS VARCHAR) AS region_key,
    CAST(cs.C_Code AS VARCHAR) || ':' || CAST(cs.CSub_Code AS VARCHAR) AS region_label,
    NULLIF(TRIM(cs.CurrentPresence), '')                               AS presence_status,
    NULLIF(TRIM(cs.Status), '')                                        AS establishment_status,
    CAST(NULL AS INTEGER)                                              AS threatened_flag,
    NULLIF(TRIM(cs.Abundance), '')                                     AS abundance,
    CAST(NULL AS VARCHAR)                                              AS importance,
    NULLIF(TRIM(cs.Comments), '')                                      AS comment
FROM read_parquet('${FISHBASE_DIR}/countrysub.parquet') cs
WHERE cs.SpecCode IS NOT NULL
  AND NULLIF(TRIM(CAST(cs.C_Code AS VARCHAR)), '') IS NOT NULL
  AND NULLIF(TRIM(CAST(cs.CSub_Code AS VARCHAR)), '') IS NOT NULL;

COPY t_taxonomy_distribution_regions TO '${EXPORT_DIR}/taxonomy_distribution_regions.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Pictures (FK → species)
-- Bilder-IDs werden ebenfalls über discere_uuid() gebildet.
-- Der zusammengesetzte Key aus speccode + picname ist stabil genug.
--
-- Lizenz-Normierung
-- Mappt den Rohwert aus dem Parquet auf einen normierten license_key.
-- is_usable = 1 nur für explizit erlaubte CC-Lizenzen (laut FishBase ToS).
-- Reihenfolge der WHEN-Klauseln ist wichtig: spezifischere zuerst,
-- da 'CC BY-NC' sonst auf 'CC BY' matchen würde.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE MACRO normalize_license(raw) AS
    CASE
        -- FishBase/SeaLifeBase-eigene Kategorien (kein CC-Label im Parquet).
        -- LIKE '%non%commercial use%' fängt auch Tippfehler-Varianten:
        --   'non-conmmercial use', 'non-com0mercial use', 'n on-commercial use'
        WHEN lower(trim(raw)) LIKE '%free use%'           THEN 'CC BY 4.0'
        WHEN lower(trim(raw)) LIKE '%non%commercial use%' THEN 'CC BY-NC 4.0'
        -- Standard CC-Labels (für zukünftige Kompatibilität)
        WHEN upper(raw) LIKE 'CC BY-NC-SA%'  THEN 'CC BY-NC-SA 4.0'
        WHEN upper(raw) LIKE 'CC BY-NC-ND%'  THEN 'CC BY-NC-ND 4.0'
        WHEN upper(raw) LIKE 'CC BY-NC%'     THEN 'CC BY-NC 4.0'
        WHEN upper(raw) LIKE 'CC BY-SA%'     THEN 'CC BY-SA 4.0'
        WHEN upper(raw) LIKE 'CC BY-ND%'     THEN 'CC BY-ND 4.0'
        WHEN upper(raw) LIKE 'CC BY%'        THEN 'CC BY 4.0'
        WHEN upper(raw) LIKE 'CC0%'          THEN 'CC0 1.0'
        WHEN upper(raw) LIKE 'PUBLIC DOMAIN' THEN 'CC0 1.0'
        ELSE                                      'ARR'
    END;

CREATE OR REPLACE MACRO is_usable_license(raw) AS
    CASE
        WHEN lower(trim(raw)) LIKE '%free use%'           THEN 1
        WHEN lower(trim(raw)) LIKE '%non%commercial use%' THEN 1
        WHEN upper(raw) LIKE 'CC BY%'        THEN 1
        WHEN upper(raw) LIKE 'CC0%'          THEN 1
        WHEN upper(raw) LIKE 'PUBLIC DOMAIN' THEN 1
        ELSE                                      0
    END;

COPY (
    SELECT
        discere_uuid('fishbase', 'pic', CAST(p.speccode AS VARCHAR) || ':' || p.picname)  AS id,
        sp.id                                                                              AS species,
        p.picname                                                                          AS picname,
        p.picturetype                                                                      AS picturetype,
        p.lifestage                                                                        AS lifestage,
        p.authname                                                                         AS author,
        p.copyright                                                                        AS copyright,
        CONCAT('https://fishbase.net.br/images/species/', p.picname)                      AS url,
        'fishbase'                                                                         AS origin,
        normalize_license(COALESCE(p.copyright, ''))                                      AS license_key,
        is_usable_license(COALESCE(p.copyright, ''))                                      AS is_usable
    FROM read_parquet('${FISHBASE_DIR}/picturesmain.parquet') p
    LEFT JOIN t_species sp ON sp.external_id = CAST(p.speccode AS VARCHAR)
    WHERE p.picturetype IN (
        'photo', 'underwater photo', 'occurrence', 'aquarium photo',
        'public aquarium', 'color drawing', 'b/w drawing',
        'b/w drawing with inserts', 'Randall''s tank photos'
    )
    UNION ALL
    SELECT
        discere_uuid('fishbase', 'fieldguide', CAST(fg.speccode AS VARCHAR) || ':' || fg.picname)  AS id,
        sp.id                                                                                       AS species,
        fg.picname                                                                                  AS picname,
        'field guide'                                                                               AS picturetype,
        'unsexed'                                                                                   AS lifestage,
        NULL                                                                                        AS author,
        NULL                                                                                        AS copyright,
        CONCAT('https://fishbase.net.br/images/species/', fg.picname)                              AS url,
        'fishbase'                                                                                  AS origin,
        'ARR'                                                                                       AS license_key,
        0                                                                                           AS is_usable
    FROM read_parquet('${FISHBASE_DIR}/fieldguide_pic.parquet') fg
    LEFT JOIN t_species sp ON sp.external_id = CAST(fg.speccode AS VARCHAR)
)
TO '${EXPORT_DIR}/pictures.csv' (FORMAT csv, HEADER true);
