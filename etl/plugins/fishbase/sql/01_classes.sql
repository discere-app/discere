COPY (
    SELECT
        uuid()     AS id,
        classnum   AS external_id,
        'fishbase' AS external_source,
        class      AS name,
        commonName AS common_name,
        superclass AS super_class
    FROM read_parquet('${FISHBASE_DIR}/classes.parquet')
) TO '${EXPORT_DIR}/classes.csv' (FORMAT csv, HEADER true);
