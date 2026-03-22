COPY (
    SELECT
        uuid()     AS id,
        gencode    AS external_id,
        'fishbase' AS external_source,
        genname    AS name,
        subfamily  AS subfamily,
        gencomname AS common_name,
        famcode    AS family
    FROM read_parquet('${FISHBASE_DIR}/genera.parquet')
) TO '${EXPORT_DIR}/genera.csv' (FORMAT csv, HEADER true);
