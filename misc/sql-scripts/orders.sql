ATTACH DATABASE ':memory:' AS duckdb;
ATTACH DATABASE '/Users/fabian/projekte/aqua-flip/aqua_flash/assets/database/aquaflash.db' AS sqlite_db;

CREATE TEMPORARY TABLE temp_orders AS
SELECT * FROM read_parquet('/Users/fabian/projekte/fishbase/data/fb/v24.07/parquet/orders.parquet');

create table orders
(
    id             TEXT not null
        constraint orders_pk
            primary key,
    name           TEXT not null,
    common_name_en TEXT,
    common_name_de TEXT,
    common_name_fr TEXT,
    common_name_es TEXT,
    class          TEXT
        constraint orders_classes_FK
            references classes
);

DELETE FROM sqlite_db.orders;

insert into sqlite_db.orders (id, name, common_name_en, common_name_de, common_name_fr, common_name_es, class)
SELECT
    ordnum,
    "order",
    commonName,
    commonName_German,
    commonName_French,
    commonName_Spanish,
    classNum
FROM temp_orders;
