ATTACH DATABASE ':memory:' AS duckdb;
ATTACH DATABASE '/Users/fabian/projekte/aqua-flip/aqua_flash/assets/database/aquaflash.db' AS sqlite_db;

CREATE TEMPORARY TABLE temp_classes AS
SELECT * FROM read_parquet('/Users/fabian/projekte/fishbase/data/fb/v24.07/parquet/classes.parquet');

create table main.classes
(
    id          TEXT not null
        constraint classes_pk
            primary key,
    name        TEXT not null,
    common_name TEXT,
    super_class TEXT not null
);




DELETE FROM sqlite_db.classes;

insert into sqlite_db.classes (id, name, common_name, super_class)
SELECT
    classnum,
    class,
    commonName,
    superclass
FROM temp_classes;

select * from temp_classes;
