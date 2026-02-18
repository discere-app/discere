CREATE VIRTUAL TABLE species_fts USING fts4(
    id UNINDEXED, 
    name, 
    common_name_en, 
    common_name_de, 
    common_name_fr, 
    common_name_es,
    tokenize='unicode61'
);

INSERT INTO species_fts (id, name, common_name_en, common_name_de, common_name_fr, common_name_es)
SELECT id, name, common_name_en, common_name_de, common_name_fr, common_name_es FROM species;

CREATE TRIGGER species_insert AFTER INSERT ON species
BEGIN
    INSERT INTO species_fts (id, name, common_name_en, common_name_de, common_name_fr, common_name_es)
    VALUES (NEW.id, NEW.name, NEW.common_name_en, NEW.common_name_de, NEW.common_name_fr, NEW.common_name_es);
END;

CREATE TRIGGER species_update AFTER UPDATE ON species
BEGIN
    DELETE FROM species_fts WHERE id = OLD.id;
    INSERT INTO species_fts (id, name, common_name_en, common_name_de, common_name_fr, common_name_es)
    VALUES (NEW.id, NEW.name, NEW.common_name_en, NEW.common_name_de, NEW.common_name_fr, NEW.common_name_es);
END;

CREATE TRIGGER species_delete AFTER DELETE ON species
BEGIN
    DELETE FROM species_fts WHERE id = OLD.id;
END;


CREATE VIRTUAL TABLE genera_fts USING fts4(
	id UNINDEXED,
	name,
	subfamily,
	common_name,
    tokenize='unicode61'
);

INSERT INTO genera_fts (id, name, subfamily, common_name)
SELECT id, name, subfamily, common_name FROM genera;

CREATE VIRTUAL TABLE families_fts USING fts4(
	id UNINDEXED,
	name,
    common_name_en, 
    common_name_de, 
    common_name_fr, 
    common_name_es,
    tokenize='unicode61'
);

INSERT INTO families_fts (id, name, common_name_en, common_name_de, common_name_fr, common_name_es)
SELECT id, name, common_name_en, common_name_de, common_name_fr, common_name_es FROM families; 

CREATE VIRTUAL TABLE orders_fts USING fts4(
	id UNINDEXED,
	name,
	common_name_en, 
    common_name_de, 
    common_name_fr, 
    common_name_es,
    tokenize='unicode61'
);

INSERT INTO orders_fts (id, name, common_name_en, common_name_de, common_name_fr, common_name_es)
SELECT id, name, common_name_en, common_name_de, common_name_fr, common_name_es FROM orders;

CREATE VIRTUAL TABLE classes_fts USING fts4(
	id UNINDEXED,
	name,
	common_name,
	super_class,
    tokenize='unicode61'
);

INSERT INTO classes_fts (id, name, common_name, super_class)
SELECT id, name, common_name, super_class FROM classes;