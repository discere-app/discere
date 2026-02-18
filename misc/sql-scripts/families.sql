ATTACH DATABASE ':memory:' AS duckdb;
ATTACH DATABASE '/Users/fabian/projekte/aqua-flip/aqua_flash/assets/database/aquaflash.db' AS sqlite_db;

CREATE TEMPORARY TABLE temp_families AS
SELECT * FROM read_parquet('/Users/fabian/projekte/fishbase/data/fb/v24.07/parquet/families.parquet');

create table sqlite_db.families
(
    id             TEXT
        primary key,
    name           TEXT,
    common_name_en TEXT,
    common_name_de TEXT,
    common_name_fr TEXT,
    common_name_es TEXT,
    "order"        TEXT
);




DELETE FROM sqlite_db.families;

insert into sqlite_db.families (id, name, common_name_en, common_name_de, common_name_fr, common_name_es, "order")
SELECT
    famcode,
    family,
    commonName,
    commonName_German,
    commonName_French,
    commonName_Spanish,
    ordnum
FROM temp_families;

select * from temp_families;
