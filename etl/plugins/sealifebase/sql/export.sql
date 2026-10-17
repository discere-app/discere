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
-- Platzhalter
-- SeaLifeBase führt die Art „DummyGenus DummySpecies“ (v26.06: SpecCode
-- 174673) ohne Gattung, Familie und Beiträge. Sie ist kein Taxon und wird
-- wie die Platzhalter von FishBase samt allen Beiträgen nicht exportiert.
-- Erkannt wird sie am Namen, denn einen eigenen Code wie FishBase GenCode 0
-- hat sie nicht.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_placeholder_species AS
SELECT SpecCode
FROM read_parquet('${SLB_DIR}/species.parquet')
WHERE lower(trim(Genus)) = 'dummygenus'
   OR lower(trim(Species)) = 'dummyspecies';

-- Ein leerer oder nicht numerischer SpecCode ist kein Platzhalter.
CREATE OR REPLACE MACRO is_placeholder_species(code) AS
    COALESCE(TRY_CAST(code AS INTEGER) IN (SELECT SpecCode FROM t_placeholder_species), false);

-- ---------------------------------------------------------------------------
-- Doppelte Codes (v26.06: drei Ordnum) — Regel und Bericht in
-- core/sql/source_codes.sql. Entitäten entstehen nur aus src_classes,
-- src_orders, src_families, src_genera und src_species; die Ordnung einer
-- Familie steht in t_family_order.
-- ---------------------------------------------------------------------------
-- @include source_codes.sql

-- ---------------------------------------------------------------------------
-- Classes
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_classes AS
SELECT
    discere_uuid('sealifebase', 'class', classnum)  AS id,
    CAST(classnum AS VARCHAR)                       AS external_id,
    'sealifebase'                                   AS external_source,
    class                                           AS name,
    CAST(NULL AS VARCHAR)                           AS body_shape,
    phylum                                          AS super_class  -- SLB hat kein superclass; Phylum als Ersatz
FROM src_classes;

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
    o.SisterOrder                                   AS sister_order,
    c.id                                            AS class
FROM src_orders o
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
    CAST(NULL AS VARCHAR)                             AS body_shape,
    f.Division                                        AS division,
    o.id                                              AS "order"
FROM src_families f
JOIN t_family_order fo ON fo.famcode = f.famcode
LEFT JOIN t_orders o ON o.external_id = CAST(fo.ordnum AS VARCHAR);

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
    CAST(NULL AS VARCHAR)                            AS body_shape,
    f.id                                             AS family
FROM src_genera g
LEFT JOIN t_families f ON f.external_id = CAST(g.famcode AS VARCHAR);

COPY t_genera TO '${EXPORT_DIR}/genera.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Ecology (für Habitat-Verdichtung, key = SpecCode)
-- SeaLifeBase nutzt dieselbe Tabelle wie FishBase, aber mit leicht abweichender
-- Schreibweise einzelner Bool-Spalten.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_ecology AS
SELECT
    CAST(e.SpecCode AS VARCHAR) AS external_id,
    MAX(e.FoodTroph)            AS food_troph,
    CASE
        WHEN MAX(CASE WHEN COALESCE(e.FreshWater, 0) <> 0 THEN 1 ELSE 0 END) = 1
          AND MAX(CASE WHEN COALESCE(e.Stream, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'freshwater stream'
        WHEN MAX(CASE WHEN COALESCE(e.FreshWater, 0) <> 0 THEN 1 ELSE 0 END) = 1
          AND MAX(CASE WHEN COALESCE(e.Lakes, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'freshwater lake'
        WHEN MAX(CASE WHEN COALESCE(e.FreshWater, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'freshwater'
        WHEN MAX(CASE WHEN COALESCE(e.Mangroves, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'mangroves'
        WHEN MAX(CASE WHEN COALESCE(e.Estuaries, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'estuary'
        WHEN MAX(CASE WHEN COALESCE(e.SeaGrassBeds, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'seagrass beds'
        WHEN MAX(CASE WHEN COALESCE(e.CoralReefs, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'coral reef'
        WHEN MAX(CASE WHEN COALESCE(e.Lagoons, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'lagoon'
        WHEN MAX(CASE WHEN COALESCE(e.caves, 0) <> 0 THEN 1 ELSE 0 END) = 1
          OR MAX(CASE WHEN COALESCE(e.Cave, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'cave'
        WHEN MAX(CASE WHEN COALESCE(e.Oceanic, 0) <> 0 THEN 1 ELSE 0 END) = 1
          AND MAX(CASE WHEN COALESCE(e.Epipelagic, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'open ocean (epipelagic)'
        WHEN MAX(CASE WHEN COALESCE(e.Oceanic, 0) <> 0 THEN 1 ELSE 0 END) = 1
          AND MAX(CASE WHEN COALESCE(e.mesopelagic, 0) <> 0 THEN 1 ELSE 0 END) = 1 THEN 'open ocean (mesopelagic)'
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
FROM read_parquet('${SLB_DIR}/ecology.parquet') e
GROUP BY e.SpecCode;

-- ---------------------------------------------------------------------------
-- Gattung je Art
-- Eine Art nennt ihre Gattung über GenCode. Bei einigen Arten fehlt er
-- (v26.06: 154), der Gattungsname steht aber in der Spalte Genus. Dann gilt
-- die SeaLifeBase-Gattung dieses Namens, wenn es genau eine gibt: Gattungs-
-- namen sind in SeaLifeBase nicht eindeutig (v26.06: 87 doppelte), und ein
-- mehrdeutiger Name ordnet nichts zu. Ohne Treffer bleibt die Gattung leer.
--
-- Die so gefundene Gattung gilt nur, wenn sie zur Art passt. Die Art nennt
-- mit FamCode auch selbst eine Familie, und beide Angaben widersprechen sich
-- in SeaLifeBase gelegentlich bis hinauf zum Stamm (v26.06: Hydrozoen unter
-- einer Rotalgen-Gattung). Welche Angabe stimmt, lässt sich aus der Quelle
-- allein nicht entscheiden, und eine falsche Einordnung ist schlimmer als
-- keine. Verglichen wird über die Kette, die die DB zeigt: Familie → Ordnung
-- (t_family_order) → Klasse (ClassNum der Ordnung) → Stamm (Phylum der
-- Klasse). Die eigenen Felder ClassNum und Phylum der Familien bleiben außen
-- vor; sie widersprechen der Kette bei Hunderten Familien und erscheinen
-- nirgends. Nur unter einem doppelten Ordnum wählen Name und ClassNum der
-- Familie die Ordnung (core/sql/source_codes.sql).
--
--   - Name der Gattung ungleich Genus der Art (trim, ohne Groß- und
--     Kleinschreibung): Die Gattung ist eine andere, als die Art nennt.
--     Gattung leer, Grund „Name“.
--   - Gleiche Familie: Die Gattung passt.
--   - Ordnung einer Seite unklar — ohne Ordnung (auch unter einem doppelten
--     Ordnum, der sich nicht auflösen ließ), ohne Familie, Kette darüber
--     unvollständig, oder Klasse bzw. Stamm ein
--     Rang-Platzhalter („Not assigned“, Muster wie core/sql/placeholders.sql
--     aus core/data/placeholder_patterns.csv): Ein Vergleich ist nicht
--     möglich, denn zwei Familien unter derselben Platzhalter-Klasse können
--     in verschiedenen echten Klassen stehen. Gattung leer, Grund „Ordnung
--     unklar“.
--   - Anderer Stamm oder andere Klasse: Gattung leer, Grund „Stamm“ bzw.
--     „Klasse“.
--   - Nur Familie oder Ordnung anders, Klasse und Stamm gleich: Die Gattung
--     bleibt. Das sind meist Umstellungen, bei denen eine der beiden Angaben
--     veraltet ist; welche, sagt die Quelle nicht.
--
-- Jede Art ohne GenCode und jede, deren Gattung nicht passt, steht im
-- Build-Bericht (genus_report.tsv).
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_genus_names AS
SELECT TRIM(GenName) AS gen_name, COUNT(*) AS matches, MIN(GenCode) AS gencode
FROM src_genera
GROUP BY TRIM(GenName);

CREATE TEMP TABLE t_placeholder_patterns AS
SELECT pattern FROM read_csv('${PLACEHOLDER_PATTERNS}', header = true, columns = {'pattern': 'VARCHAR'});

CREATE OR REPLACE MACRO is_rank_placeholder(name) AS
    EXISTS (SELECT 1 FROM t_placeholder_patterns p WHERE LOWER(TRIM(name)) GLOB p.pattern);

-- Kette über einer Familie, wie sie exportiert wird: Ordnung aus
-- t_family_order (bei doppeltem Ordnum über Name und ClassNum der Familie).
CREATE TEMP TABLE t_family_chain AS
SELECT
    f.FamCode                        AS famcode,
    TRIM(f.Family)                   AS family,
    o.Ordnum                         AS ordnum,
    TRIM(o."Order")                  AS order_name,
    c.ClassNum                       AS classnum,
    TRIM(c.Class)                    AS class_name,
    NULLIF(LOWER(TRIM(c.Phylum)), '') AS phylum,
    TRIM(c.Phylum)                   AS phylum_name,
    is_rank_placeholder(c.Phylum)    AS placeholder_phylum,
    is_rank_placeholder(c.Class) OR is_rank_placeholder(c.Phylum) AS placeholder_class
FROM src_families f
JOIN t_family_order fo ON fo.famcode = f.FamCode
LEFT JOIN src_orders o ON o.Ordnum = fo.ordnum
LEFT JOIN src_classes c ON c.ClassNum = o.ClassNum;

CREATE TEMP TABLE t_species_genus_check AS
WITH candidates AS (
    SELECT
        s.SpecCode                                                      AS speccode,
        CONCAT_WS(' ', TRIM(s.Genus), TRIM(s.Species))                  AS species_name,
        TRIM(s.Genus)                                                   AS genus_name,
        s.FamCode                                                       AS famcode,
        s.GenCode IS NULL                                               AS by_name,
        COALESCE(n.matches, 0)                                          AS name_matches,
        CASE WHEN s.GenCode IS NOT NULL THEN s.GenCode
             WHEN n.matches = 1         THEN n.gencode
        END                                                             AS candidate
    FROM src_species s
    LEFT JOIN t_genus_names n
      ON s.GenCode IS NULL AND n.gen_name = TRIM(s.Genus)
    WHERE NOT is_placeholder_species(s.SpecCode)
)
SELECT
    c.*,
    TRIM(g.GenName)                                                     AS candidate_name,
    CASE
        WHEN c.candidate IS NULL                                        THEN NULL
        WHEN LOWER(TRIM(g.GenName)) IS DISTINCT FROM LOWER(c.genus_name) THEN 'Name'
        WHEN g.FamCode = c.famcode                                      THEN 'passt'
        WHEN cs.ordnum IS NULL OR cg.ordnum IS NULL
          OR cs.classnum IS NULL OR cg.classnum IS NULL
          OR cs.phylum IS NULL OR cg.phylum IS NULL                     THEN 'Ordnung unklar'
        WHEN cs.phylum <> cg.phylum
         AND NOT cs.placeholder_phylum AND NOT cg.placeholder_phylum    THEN 'Stamm'
        WHEN cs.placeholder_class OR cg.placeholder_class               THEN 'Ordnung unklar'
        WHEN cs.classnum <> cg.classnum                                 THEN 'Klasse'
        WHEN cs.ordnum <> cg.ordnum                                     THEN 'Ordnung'
        ELSE                                                                 'Familie'
    END                                                                 AS verdict,
    -- Beide Ketten für den Bericht: Familie / Ordnung / Klasse / Stamm,
    -- Unbekanntes als „?“.
    CONCAT_WS(' / ', COALESCE(cg.family, '?'), COALESCE(cg.order_name, '?'),
              COALESCE(cg.class_name, '?'), COALESCE(cg.phylum_name, '?'))   AS genus_chain,
    CONCAT_WS(' / ', COALESCE(cs.family, '?'), COALESCE(cs.order_name, '?'),
              COALESCE(cs.class_name, '?'), COALESCE(cs.phylum_name, '?'))   AS species_chain
FROM candidates c
LEFT JOIN src_genera g ON g.GenCode = c.candidate
LEFT JOIN t_family_chain cg ON cg.famcode = g.FamCode
LEFT JOIN t_family_chain cs ON cs.famcode = c.famcode;

CREATE TEMP TABLE t_species_genus AS
SELECT
    speccode,
    CASE WHEN verdict IN ('passt', 'Ordnung', 'Familie') THEN candidate END AS gencode
FROM t_species_genus_check;

COPY (
    SELECT
        CASE
            WHEN verdict IS NULL                  THEN 'genus_unresolved'
            WHEN verdict IN ('Name', 'Ordnung unklar', 'Stamm', 'Klasse')
                                                  THEN 'genus_rejected'
            WHEN verdict = 'Ordnung'              THEN 'genus_kept_order_differs'
            WHEN verdict = 'Familie'              THEN 'genus_kept_family_differs'
            ELSE                                       'genus_by_name'
        END,
        CAST(speccode AS VARCHAR),
        species_name,
        CASE
            WHEN verdict IS NULL AND name_matches = 0 THEN 'keine Gattung dieses Namens'
            WHEN verdict IS NULL THEN CAST(name_matches AS VARCHAR) || ' Gattungen dieses Namens'
            WHEN verdict = 'passt' THEN 'GenCode ' || CAST(candidate AS VARCHAR)
            ELSE CASE WHEN verdict IN ('Name', 'Ordnung unklar', 'Stamm', 'Klasse')
                      THEN verdict || ': ' ELSE '' END
                 || CASE WHEN by_name THEN 'über den Namen, ' ELSE '' END
                 || 'GenCode ' || CAST(candidate AS VARCHAR) || ' ' || candidate_name
                 || ' (' || genus_chain || '), Art: ' || species_chain
        END
    FROM t_species_genus_check
    WHERE by_name OR verdict IS DISTINCT FROM 'passt'
    ORDER BY 1, 3, 2
)
TO '${EXPORT_DIR}/genus_report.tsv' (FORMAT csv, DELIMITER '\t', HEADER false, QUOTE '');

-- ---------------------------------------------------------------------------
-- Species (FK → genera)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_species AS
SELECT
    discere_uuid('sealifebase', 'species', s.speccode)                  AS id,
    CAST(s.speccode AS VARCHAR)                                         AS external_id,
    'sealifebase'                                                       AS external_source,
    s.species                                                           AS name,
    s.Length                                                            AS max_length_cm,
    COALESCE(s.DepthRangeShallow, s.DepthRangeComShallow)               AS depth_min_m,
    COALESCE(s.DepthRangeDeep, s.DepthRangeComDeep)                     AS depth_max_m,
    COALESCE(e.habitat, NULLIF(TRIM(s.DemersPelag), ''))                AS habitat,
    s.Vulnerability                                                     AS vulnerability,
    NULLIF(TRIM(s.Dangerous), '')                                       AS dangerous_to_humans,
    NULLIF(TRIM(s.Importance), '')                                      AS fisheries_importance,
    s.LongevityWild                                                     AS longevity_years,
    NULLIF(TRIM(s.BodyShapeI), '')                                      AS body_shape,
    e.food_troph                                                        AS trophic_level_food,
    g.id                                                                AS genus,
    'active'                                                            AS status,
    NULL                                                                AS deprecated_at
FROM src_species s
JOIN t_species_genus sg ON sg.speccode = s.speccode
LEFT JOIN t_ecology e ON e.external_id = CAST(s.speccode AS VARCHAR)
LEFT JOIN t_genera g ON g.external_id = CAST(sg.gencode AS VARCHAR)
ORDER BY s.speccode;

COPY t_species TO '${EXPORT_DIR}/species.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Species Scientific Names
-- Wissenschaftliche Namen für Imports und Alias-Lookups.
-- Beinhaltet pro Species genau einen kanonischen Namen aus species.parquet
-- sowie zusätzliche Arten-Synonyme aus synonyms.parquet.
--
-- Der kanonische Name ist Gattung und Epitheton. Ohne Gattung — verworfen,
-- weil sie nicht zur Familie der Art passt, oder nicht auflösbar — steht der
-- Gattungsname aus der Spalte Genus der Art: Das ist der Name, den die Quelle
-- der Art gibt, und er ordnet sie keiner Gattung zu.
--
-- Je Art und normalisiertem Namen eine Zeile (Schlüssel der Tabelle), fest
-- gewählt: Führt die Quelle den kanonischen Namen auch als Synonym der Art,
-- bleibt der kanonische. Unter gleichnamigen Synonymen gewinnt der Status,
-- der den Namen am deutlichsten der Art zuschreibt (synonym, ambiguous
-- synonym, misapplied name — ein falsch angewandter Name ist für Abgleich
-- und Nachfolger kein Kandidat), danach source_ref und die übrigen Spalten.
-- ---------------------------------------------------------------------------
COPY (
    SELECT
        species_id,
        name,
        normalized_name,
        name_status,
        source,
        source_ref,
        is_preferred,
        synonymy,
        combination,
        misspelling
    FROM (
        -- Kanonischer Species-Name
        SELECT
            sp.id                                                  AS species_id,
            CONCAT(COALESCE(g.GenName, TRIM(s.Genus)), ' ', s.species) AS name,
            LOWER(CONCAT(TRIM(COALESCE(g.GenName, s.Genus)), ' ', TRIM(s.species))) AS normalized_name,
            'valid'                                                AS name_status,
            'sealifebase'                                          AS source,
            CAST(s.SpecCode AS VARCHAR)                            AS source_ref,
            1                                                      AS is_preferred,
            CAST(NULL AS VARCHAR)                                  AS synonymy,
            CAST(NULL AS VARCHAR)                                  AS combination,
            0                                                      AS misspelling
        FROM src_species s
        JOIN t_species_genus sg
          ON sg.speccode = s.speccode
        LEFT JOIN src_genera g
          ON g.gencode = sg.gencode
        JOIN t_species sp
          ON sp.external_id = CAST(s.speccode AS VARCHAR)
        WHERE NULLIF(TRIM(COALESCE(g.GenName, s.Genus)), '') IS NOT NULL

        UNION ALL

        -- Species-Synonyme / Fehl- und Alt-Kombinationen
        SELECT
            sp.id                                                  AS species_id,
            CONCAT(TRIM(syn.SynGenus), ' ', TRIM(syn.SynSpecies))  AS name,
            LOWER(CONCAT(TRIM(syn.SynGenus), ' ', TRIM(syn.SynSpecies))) AS normalized_name,
            LOWER(TRIM(syn.Status))                                AS name_status,
            'sealifebase'                                          AS source,
            CAST(syn.SynonymsRef AS VARCHAR)                       AS source_ref,
            0                                                      AS is_preferred,
            NULLIF(TRIM(syn.Synonymy), '')                         AS synonymy,
            NULLIF(TRIM(syn.Combination), '')                      AS combination,
            COALESCE(syn.Misspelling, 0)                           AS misspelling
        FROM read_parquet('${SLB_DIR}/synonyms.parquet') syn
        JOIN t_species sp
          ON sp.external_id = CAST(syn.SpecCode AS VARCHAR)
        WHERE syn.TaxonLevel = 'Species'
          AND syn.SpecCode IS NOT NULL
          AND NULLIF(TRIM(syn.SynGenus), '') IS NOT NULL
          AND NULLIF(TRIM(syn.SynSpecies), '') IS NOT NULL
          AND COALESCE(TRIM(syn.Status), '') NOT IN (
              'accepted name',
              'provisionally accepted name'
          )
    )
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY species_id, normalized_name, source
        ORDER BY is_preferred DESC,
                 CASE name_status
                     WHEN 'synonym'           THEN 1
                     WHEN 'ambiguous synonym' THEN 2
                     WHEN 'misapplied name'   THEN 3
                     ELSE 4
                 END,
                 source_ref, name_status, name, synonymy, combination, misspelling
    ) = 1
)
TO '${EXPORT_DIR}/species_scientific_names.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Mehrdeutige Namen (ambiguous_scientific_names)
-- Namen, die die Quelle als Synonym mehr als einer Art führt, über alle
-- Ebenen (TaxonLevel): Ein Name kann bei einer Art auf der Ebene Species und
-- bei einer anderen auf einer anderen Ebene stehen, und nur die erste Zeile
-- kommt in species_scientific_names. Gezählt werden Binome (Gattung und
-- Epitheton je ein Wort) an Arten dieses Exports, ohne angenommene und falsch
-- angewandte Namen — wie bei den Namen oben.
-- ---------------------------------------------------------------------------
COPY (
    SELECT
        LOWER(CONCAT(TRIM(syn.SynGenus), ' ', TRIM(syn.SynSpecies)))    AS normalized_name,
        'sealifebase'                                                    AS source,
        COUNT(DISTINCT syn.SpecCode)                                     AS species_count
    FROM read_parquet('${SLB_DIR}/synonyms.parquet') syn
    JOIN t_species sp
      ON sp.external_id = CAST(syn.SpecCode AS VARCHAR)
    WHERE NULLIF(TRIM(syn.SynGenus), '') IS NOT NULL
      AND NULLIF(TRIM(syn.SynSpecies), '') IS NOT NULL
      AND TRIM(syn.SynGenus) NOT LIKE '% %'
      AND TRIM(syn.SynSpecies) NOT LIKE '% %'
      AND COALESCE(TRIM(syn.Status), '') NOT IN (
          'accepted name',
          'provisionally accepted name',
          'misapplied name'
      )
    GROUP BY 1
    HAVING COUNT(DISTINCT syn.SpecCode) > 1
    ORDER BY 1
)
TO '${EXPORT_DIR}/ambiguous_scientific_names.csv' (FORMAT csv, HEADER true);

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
        discere_uuid('sealifebase', 'species', CAST(c.speccode AS VARCHAR)) AS entity_id,
        'species'                                                            AS entity_type,
        CASE c.language
            WHEN 'German'  THEN 'de'
            WHEN 'English' THEN 'en'
            WHEN 'French'  THEN 'fr'
            WHEN 'Spanish' THEN 'es'
        END                                                                  AS language,
        CASE WHEN CAST(c.c_code AS VARCHAR) = '9999' THEN NULL
             ELSE LPAD(CAST(c.c_code AS VARCHAR), 3, '0')
        END                                                                  AS country,
        TRIM(c.comname)                                                      AS name,
        'sealifebase'                                                        AS source,
        c.rank                                                               AS rank,
        c.preferredname                                                      AS is_preferred,
        CASE LOWER(TRIM(c.nametype))
            WHEN 'vernacular' THEN 'Vernacular'
            ELSE TRIM(c.nametype)
        END                                                                  AS name_type
    FROM read_parquet('${SLB_DIR}/comnames.parquet') c
    WHERE c.language IN ('German', 'English', 'French', 'Spanish')
      AND NOT is_placeholder_species(c.speccode)
      AND TRIM(c.comname) <> ''
      AND TRIM(c.nametype) NOT IN (
          'FAO old', 'FAO Old', 'AFS old', 'FAO alt',
          'FAO cat', 'FAO Cat', 'FAO syn', 'FAO split'
      )

    UNION ALL

    -- Order-Namen (je eine Zeile pro Sprache)
    SELECT discere_uuid('sealifebase', 'order', o.ordnum), 'order', 'en', NULL,
           TRIM(o.commonName), 'sealifebase', NULL, 1, NULL
    FROM src_orders o
    WHERE NULLIF(TRIM(o.commonName), '') IS NOT NULL

    UNION ALL

    SELECT discere_uuid('sealifebase', 'order', o.ordnum), 'order', 'de', NULL,
           TRIM(o.commonName_German), 'sealifebase', NULL, 1, NULL
    FROM src_orders o
    WHERE NULLIF(TRIM(o.commonName_German), '') IS NOT NULL

    UNION ALL

    SELECT discere_uuid('sealifebase', 'order', o.ordnum), 'order', 'fr', NULL,
           TRIM(o.commonName_French), 'sealifebase', NULL, 1, NULL
    FROM src_orders o
    WHERE NULLIF(TRIM(o.commonName_French), '') IS NOT NULL

    UNION ALL

    SELECT discere_uuid('sealifebase', 'order', o.ordnum), 'order', 'es', NULL,
           TRIM(o.commonName_Spanish), 'sealifebase', NULL, 1, NULL
    FROM src_orders o
    WHERE NULLIF(TRIM(o.commonName_Spanish), '') IS NOT NULL

    UNION ALL

    -- Family-Namen
    SELECT discere_uuid('sealifebase', 'family', f.famcode), 'family', 'en', NULL,
           TRIM(f.commonName), 'sealifebase', NULL, 1, NULL
    FROM src_families f
    WHERE NULLIF(TRIM(f.commonName), '') IS NOT NULL

    UNION ALL

    SELECT discere_uuid('sealifebase', 'family', f.famcode), 'family', 'de', NULL,
           TRIM(f.commonName_German), 'sealifebase', NULL, 1, NULL
    FROM src_families f
    WHERE NULLIF(TRIM(f.commonName_German), '') IS NOT NULL

    UNION ALL

    SELECT discere_uuid('sealifebase', 'family', f.famcode), 'family', 'fr', NULL,
           TRIM(f.commonName_French), 'sealifebase', NULL, 1, NULL
    FROM src_families f
    WHERE NULLIF(TRIM(f.commonName_French), '') IS NOT NULL

    UNION ALL

    SELECT discere_uuid('sealifebase', 'family', f.famcode), 'family', 'es', NULL,
           TRIM(f.commonName_Spanish), 'sealifebase', NULL, 1, NULL
    FROM src_families f
    WHERE NULLIF(TRIM(f.commonName_Spanish), '') IS NOT NULL

    UNION ALL

    -- Genera-Namen (nur Englisch, kein Sprachfeld in SLB)
    SELECT discere_uuid('sealifebase', 'genus', g.gencode), 'genus', 'en', NULL,
           TRIM(g.CommonName), 'sealifebase', NULL, 1, NULL
    FROM src_genera g
    WHERE NULLIF(TRIM(g.CommonName), '') IS NOT NULL

    UNION ALL

    -- Class-Namen (nur Englisch)
    SELECT discere_uuid('sealifebase', 'class', c.classnum), 'class', 'en', NULL,
           TRIM(c.commonName), 'sealifebase', NULL, 1, NULL
    FROM src_classes c
    WHERE NULLIF(TRIM(c.commonName), '') IS NOT NULL

    ORDER BY entity_type, entity_id, language, country, rank, is_preferred DESC
)
TO '${EXPORT_DIR}/common_names.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Taxonomy Traits (Species-Habitat-Tags)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_taxonomy_traits AS
SELECT DISTINCT
    discere_uuid('sealifebase', 'species', CAST(e.SpecCode AS VARCHAR)) AS entity_id,
    'species'                                                           AS entity_type,
    e.trait_key                                                         AS trait_key,
    CAST(NULL AS VARCHAR)                                               AS trait_value_text,
    CAST(NULL AS DOUBLE)                                                AS trait_value_num,
    1                                                                   AS trait_value_bool,
    'sealifebase'                                                       AS source
FROM (
    SELECT SpecCode, 'freshwater_stream_association' AS trait_key
    FROM read_parquet('${SLB_DIR}/ecology.parquet')
    WHERE COALESCE(Stream, 0) <> 0

    UNION ALL

    SELECT SpecCode, 'lake_association' AS trait_key
    FROM read_parquet('${SLB_DIR}/ecology.parquet')
    WHERE COALESCE(Lakes, 0) <> 0

    UNION ALL

    SELECT SpecCode, 'mangrove_association' AS trait_key
    FROM read_parquet('${SLB_DIR}/ecology.parquet')
    WHERE COALESCE(Mangroves, 0) <> 0

    UNION ALL

    SELECT SpecCode, 'reef_association' AS trait_key
    FROM read_parquet('${SLB_DIR}/ecology.parquet')
    WHERE COALESCE(CoralReefs, 0) <> 0

    UNION ALL

    SELECT SpecCode, 'seagrass_association' AS trait_key
    FROM read_parquet('${SLB_DIR}/ecology.parquet')
    WHERE COALESCE(SeaGrassBeds, 0) <> 0
) e
WHERE NOT is_placeholder_species(e.SpecCode);

COPY t_taxonomy_traits TO '${EXPORT_DIR}/taxonomy_traits.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Taxonomy Distribution Regions (country / countrysub)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_taxonomy_distribution_regions AS
SELECT DISTINCT
    discere_uuid('sealifebase', 'species', CAST(c.SpecCode AS VARCHAR)) AS entity_id,
    'species'                                                           AS entity_type,
    'sealifebase'                                                       AS source,
    'country'                                                           AS region_scope,
    CAST(c.C_Code AS VARCHAR)                                           AS region_key,
    CAST(c.C_Code AS VARCHAR)                                           AS region_label,
    NULLIF(TRIM(c.CurrentPresence), '')                                 AS presence_status,
    NULLIF(TRIM(c.Status), '')                                          AS establishment_status,
    c.Threatened                                                        AS threatened_flag,
    NULLIF(TRIM(c.Abundance), '')                                       AS abundance,
    NULLIF(TRIM(c.Importance), '')                                      AS importance,
    NULLIF(TRIM(c.Comments), '')                                        AS comment
FROM read_parquet('${SLB_DIR}/country.parquet') c
WHERE c.SpecCode IS NOT NULL
  AND NOT is_placeholder_species(c.SpecCode)
  AND NULLIF(TRIM(CAST(c.C_Code AS VARCHAR)), '') IS NOT NULL

UNION ALL

SELECT DISTINCT
    discere_uuid('sealifebase', 'species', CAST(cs.SpecCode AS VARCHAR))  AS entity_id,
    'species'                                                             AS entity_type,
    'sealifebase'                                                         AS source,
    'subregion'                                                           AS region_scope,
    CAST(cs.C_Code AS VARCHAR) || ':' || CAST(cs.CSub_Code AS VARCHAR)    AS region_key,
    CAST(cs.C_Code AS VARCHAR) || ':' || CAST(cs.CSub_Code AS VARCHAR)    AS region_label,
    NULLIF(TRIM(cs.CurrentPresence), '')                                  AS presence_status,
    NULLIF(TRIM(cs.Status), '')                                           AS establishment_status,
    CAST(NULL AS INTEGER)                                                 AS threatened_flag,
    NULLIF(TRIM(cs.Abundance), '')                                        AS abundance,
    CAST(NULL AS VARCHAR)                                                 AS importance,
    NULLIF(TRIM(cs.Comments), '')                                         AS comment
FROM read_parquet('${SLB_DIR}/countrysub.parquet') cs
WHERE cs.SpecCode IS NOT NULL
  AND NOT is_placeholder_species(cs.SpecCode)
  AND NULLIF(TRIM(CAST(cs.C_Code AS VARCHAR)), '') IS NOT NULL
  AND NULLIF(TRIM(CAST(cs.CSub_Code AS VARCHAR)), '') IS NOT NULL;

COPY t_taxonomy_distribution_regions TO '${EXPORT_DIR}/taxonomy_distribution_regions.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Pictures (picturesmain)
--
-- Lizenz-Normierung: identisch mit FishBase — gleiche Tabellenstruktur,
-- gleiche Lizenzbedingungen (CC BY-NC 4.0, www.sealifebase.org).
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
        discere_uuid('sealifebase', 'pic', CAST(p.speccode AS VARCHAR) || ':' || p.picname)  AS id,
        sp.id                                                                                  AS species,
        p.picname                                                                              AS picname,
        p.picturetype                                                                          AS picturetype,
        p.lifestage                                                                            AS lifestage,
        p.authname                                                                             AS author,
        p.copyright                                                                            AS copyright,
        CONCAT('https://sealifebase.org/images/species/', p.picname)                          AS url,
        'sealifebase'                                                                          AS origin,
        normalize_license(COALESCE(p.copyright, ''))                                          AS license_key,
        is_usable_license(COALESCE(p.copyright, ''))                                          AS is_usable
    FROM read_parquet('${SLB_DIR}/picturesmain.parquet') p
    LEFT JOIN t_species sp ON sp.external_id = CAST(p.speccode AS VARCHAR)
    WHERE NOT is_placeholder_species(p.speccode)
      AND p.picturetype IN (
        'photo', 'underwater photo', 'occurrence', 'aquarium photo',
        'public aquarium', 'color drawing', 'b/w drawing',
        'b/w drawing with inserts', 'Randall''s tank photos'
    )
)
TO '${EXPORT_DIR}/pictures.csv' (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------------
-- Pictures (fieldguide_pic) — optional, nicht alle SLB-Versionen enthalten diese Tabelle
-- Kein Lizenzfeld vorhanden → fix ARR / is_usable = 0.
-- Wird in import.sh separat behandelt.
-- ---------------------------------------------------------------------------
