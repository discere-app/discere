COPY (
    SELECT
        uuid()                                                                         AS id,
        s.speccode                                                                     AS external_id,
        'fishbase'                                                                     AS external_source,
        MAX(s.species)                                                                 AS name,
        MAX(s.gencode)                                                                 AS genus,
        MAX(s.commonlength)                                                            AS common_length,
        MAX(s.weight)                                                                  AS common_weight,
        STRING_AGG(DISTINCT CASE WHEN c.language = 'German'  THEN c.comname END, ';') AS common_name_de,
        STRING_AGG(DISTINCT CASE WHEN c.language = 'English' THEN c.comname END, ';') AS common_name_en,
        STRING_AGG(DISTINCT CASE WHEN c.language = 'French'  THEN c.comname END, ';') AS common_name_fr,
        STRING_AGG(DISTINCT CASE WHEN c.language = 'Spanish' THEN c.comname END, ';') AS common_name_es
    FROM read_parquet('${FISHBASE_DIR}/species.parquet') AS s
    LEFT JOIN read_parquet('${FISHBASE_DIR}/comnames.parquet') AS c
        ON s.speccode = c.speccode
        AND c.language IN ('German', 'English', 'French', 'Spanish')
    GROUP BY s.speccode
    ORDER BY s.speccode
) TO '${EXPORT_DIR}/species.csv' (FORMAT csv, HEADER true);
