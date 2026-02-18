ATTACH DATABASE ':memory:' AS duckdb;
ATTACH DATABASE '/Users/fabian/projekte/aqua-flip/aqua_flash/assets/database/aquaflash.db' AS sqlite_db;

CREATE TEMPORARY TABLE temp_genera AS
SELECT * FROM read_parquet('/Users/fabian/projekte/fishbase/data/fb/v24.07/parquet/genera.parquet');

create table genera
(
    id          TEXT not null
        constraint genera_pk
            primary key,
    name        TEXT not null,
    subfamily   TEXT,
    common_name TEXT,
    family      TEXT
        constraint genera_families_FK
            references families
);


DELETE FROM sqlite_db.genera;

INSERT INTO sqlite_db.genera (id, name, subfamily, common_name, family)
SELECT
    gencode,
    genname,
    subfamily,
    gencomname,
    famcode
FROM temp_genera;