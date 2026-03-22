COPY (
    SELECT
        uuid()             AS id,
        famcode            AS external_id,
        'fishbase'         AS external_source,
        family             AS name,
        commonName         AS common_name_en,
        commonName_German  AS common_name_de,
        commonName_French  AS common_name_fr,
        commonName_Spanish AS common_name_es,
        ordnum             AS "order"
    FROM read_parquet('${FISHBASE_DIR}/families.parquet')
) TO '${EXPORT_DIR}/families.csv' (FORMAT csv, HEADER true);
