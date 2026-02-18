ATTACH DATABASE ':memory:' AS duckdb;

CREATE TEMPORARY TABLE temp_pictures AS
SELECT * FROM read_parquet('/Users/fabian/projekte/fishbase/data/fb/v24.07/parquet/picturesmain.parquet');


CREATE TEMPORARY TABLE temp_fg AS
SELECT * FROM read_parquet('/Users/fabian/projekte/fishbase/data/fb/v24.07/parquet/fieldguide_pic.parquet');

ATTACH DATABASE '/Users/fabian/projekte/aqua-flip/aqua_flash/assets/database/aquaflash.db' AS sqlite_db;


CREATE TABLE pictures (
                          id UUID PRIMARY KEY,
                          species TEXT,
                          picname TEXT,
                          picturetype TEXT,
                          lifestage TEXT,
                          author TEXT,
                          copyright TEXT,
                          url TEXT,
                          origin TEXT NOT NULL
                              FOREIGN KEY (species) REFERENCES species(id)
);
CREATE INDEX idx_species ON pictures(species);


INSERT INTO sqlite_db.pictures (id, species, picname, picturetype, lifestage, url, copyright, author, origin)
SELECT
    UUID(),
    speccode,
    picname,
    picturetype,
    lifestage,
    CONCAT('https://fishbase.net.br/images/species/',
           picname) AS URL,
    authname,
    copyright,
    'fishbase' AS origin
FROM
    temp_pictures AS p
WHERE
    p.picturetype IN ('photo', 'underwater photo', 'occurrence', 'aquarium photo', 'public aquarium' , 'color drawing', 'b/w drawing', 'b/w drawing with inserts', 'Randall''s tank photos')
UNION
SELECT
    UUID(),
    speccode,
    picname,
    'field guide',
    'unsexted',
    CONCAT('https://fishbase.net.br/images/species/',
           picname) AS URL,
    null,
    null,
    'fishbase' AS origin
FROM temp_fg as fg
