COPY (
    SELECT
        uuid()      AS id,
        speccode    AS species,
        picname     AS picname,
        picturetype AS picturetype,
        lifestage   AS lifestage,
        authname    AS author,
        copyright   AS copyright,
        CONCAT('https://fishbase.net.br/images/species/', picname) AS url,
        'fishbase'  AS origin
    FROM read_parquet('${FISHBASE_DIR}/picturesmain.parquet')
    WHERE picturetype IN (
        'photo', 'underwater photo', 'occurrence', 'aquarium photo',
        'public aquarium', 'color drawing', 'b/w drawing',
        'b/w drawing with inserts', 'Randall''s tank photos'
    )
    UNION ALL
    SELECT
        uuid()        AS id,
        speccode      AS species,
        picname       AS picname,
        'field guide' AS picturetype,
        'unsexed'     AS lifestage,
        NULL          AS author,
        NULL          AS copyright,
        CONCAT('https://fishbase.net.br/images/species/', picname) AS url,
        'fishbase'    AS origin
    FROM read_parquet('${FISHBASE_DIR}/fieldguide_pic.parquet')
) TO '${EXPORT_DIR}/pictures.csv' (FORMAT csv, HEADER true);
