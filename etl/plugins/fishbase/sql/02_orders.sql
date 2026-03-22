COPY (
    SELECT
        uuid()             AS id,
        ordnum             AS external_id,
        'fishbase'         AS external_source,
        "order"            AS name,
        commonName         AS common_name_en,
        commonName_German  AS common_name_de,
        commonName_French  AS common_name_fr,
        commonName_Spanish AS common_name_es,
        classNum           AS class
    FROM read_parquet('${FISHBASE_DIR}/orders.parquet')
) TO '${EXPORT_DIR}/orders.csv' (FORMAT csv, HEADER true);
