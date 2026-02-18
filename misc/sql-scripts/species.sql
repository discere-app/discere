ATTACH DATABASE ':memory:' AS duckdb;

CREATE TEMPORARY TABLE temp_species AS
SELECT * FROM read_parquet('/Users/fabian/projekte/fishbase/data/fb/v24.07/parquet/species.parquet');

CREATE TEMPORARY TABLE temp_comnames AS
SELECT * FROM parquet_scan('/Users/fabian/projekte/fishbase/data/fb/v24.07/parquet/comnames.parquet');

ATTACH DATABASE '/Users/fabian/projekte/aqua-flip/aqua_flash/assets/database/aquaflash.db' AS sqlite_db;

-- Tabelle erstellen falls nicht vorhanden
CREATE TABLE species (
                         id TEXT NOT NULL,
                         name TEXT NOT NULL,
                         common_name_de TEXT,
                         common_name_en TEXT,
                         common_name_fr TEXT,
                         common_name_es TEXT,
                         common_length NUMERIC,
                         common_weight NUMERIC,
                         genus TEXT NOT NULL,
                         fb_pictures TEXT,
                         CONSTRAINT species_pk PRIMARY KEY (id)
);

-- falls nicht geht, foreign keys deaktivieren in IntelliJ (pragma foreign_keys = off und dort ausführen)
DELETE FROM sqlite_db.species;
INSERT INTO sqlite_db.species (id, common_name_de, common_name_en, common_name_fr, common_name_es, name, genus, common_length, common_weight)
SELECT 
    s.speccode,
	 STRING_AGG(
	    DISTINCT CASE WHEN c.language = 'German' THEN c.comname ELSE NULL END,
	    ';'
	) AS comname_de,
	STRING_AGG(
	    DISTINCT CASE WHEN c.language = 'English' THEN c.comname ELSE NULL END,
	    ';'
	) AS comname_en,
	STRING_AGG(
	    DISTINCT CASE WHEN c.language = 'French' THEN c.comname ELSE NULL END,
	    ';'
	) AS comname_fr,
	STRING_AGG(
	    DISTINCT CASE WHEN c.language = 'Spanish' THEN c.comname ELSE NULL END,
	    ';'
	) AS comname_sp,
    MAX(s.species) AS species, 
    MAX(s.gencode) AS genus, 
    MAX(s.commonlength) AS commonlength, 
    MAX(s.weight) AS weight
FROM 
    temp_species AS s
JOIN 
    temp_comnames AS c
ON 
    s.speccode = c.speccode
WHERE 
    c.language IN ('German', 'English', 'French', 'Spanish')
GROUP BY
    s.speccode
ORDER BY 
    s.speccode;
