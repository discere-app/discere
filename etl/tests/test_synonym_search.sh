#!/usr/bin/env bash
# Tests für die Suche über Synonyme (species_synonyms_fts, befüllt von
# core/sql/rebuild_fts.sql): Eine aktive Art ist unter jedem Namen zu finden,
# den sie als Synonym führt.

# Legt unter $TEST_TMP/ref.db Arten mit diesen Namen an (P = bevorzugt,
# S = Synonym, M = falsch angewandt):
#
#   amphiprion ocellaris    P bei 1
#   amphiprion bicolor      S bei 1, in sealifebase „Amphiprion Bicolor“
#   amphiprion vetus        M bei 1
#   amphiprion percula      P bei 2
#   amphiprion communis     S bei 2 und bei 3
#   amphiprion clarkii      P bei 3 (fishbase), S bei 3 (sealifebase)
#   amphiprion akallopisos  P bei 4 (deprecated)
#   amphiprion sebae        S bei 4
create_synonym_search_db() {
    DB="$TEST_TMP/ref.db"
    "$ETL_DIR/core/create_db.sh" --output "$DB" > /dev/null 2>&1
    sqlite3 "$DB" << 'SQL'
INSERT INTO species (id, external_id, external_source, name, status) VALUES
    ('discere:species:1', '1', 'fishbase', 'ocellaris',   'active'),
    ('discere:species:2', '2', 'fishbase', 'percula',     'active'),
    ('discere:species:3', '3', 'fishbase', 'clarkii',     'active'),
    ('discere:species:4', '4', 'fishbase', 'akallopisos', 'deprecated');
INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
    ('discere:species:1', 'Amphiprion ocellaris',   'amphiprion ocellaris',   'valid',           'fishbase',    1),
    ('discere:species:1', 'Amphiprion bicolor',     'amphiprion bicolor',     'synonym',         'fishbase',    0),
    ('discere:species:1', 'Amphiprion Bicolor',     'amphiprion bicolor',     'synonym',         'sealifebase', 0),
    ('discere:species:1', 'Amphiprion vetus',       'amphiprion vetus',       'misapplied name', 'fishbase',    0),
    ('discere:species:2', 'Amphiprion percula',     'amphiprion percula',     'valid',           'fishbase',    1),
    ('discere:species:2', 'Amphiprion communis',    'amphiprion communis',    'synonym',         'fishbase',    0),
    ('discere:species:3', 'Amphiprion communis',    'amphiprion communis',    'synonym',         'fishbase',    0),
    ('discere:species:3', 'Amphiprion clarkii',     'amphiprion clarkii',     'valid',           'fishbase',    1),
    ('discere:species:3', 'Amphiprion clarkii',     'amphiprion clarkii',     'synonym',         'sealifebase', 0),
    ('discere:species:4', 'Amphiprion akallopisos', 'amphiprion akallopisos', 'valid',           'fishbase',    1),
    ('discere:species:4', 'Amphiprion sebae',       'amphiprion sebae',       'synonym',         'fishbase',    0);
SQL
}

rebuild_fts() {
    run_capture sqlite3 "$DB" < "$ETL_DIR/core/sql/rebuild_fts.sql"
}

synonym_rows() {
    sqlite3 -separator ' → ' "$DB" "SELECT name, species_id FROM species_synonyms_fts ORDER BY 1, 2;"
}

# Arten, die die Suche nach <ausdruck> über ein Synonym findet, in der Form,
# in der die App sie abfragt.
species_matching() {
    sqlite3 "$DB" "SELECT id FROM species
                   WHERE id IN (SELECT species_id FROM species_synonyms_fts
                                WHERE species_synonyms_fts MATCH '$1')
                   ORDER BY id;"
}

# Je aktive Art und Name eine Zeile für jedes Synonym, auch eines zweier
# Arten. Bevorzugte und falsch angewandte Namen, Synonyme veralteter Arten
# und ein Name, den eine andere Quelle derselben Art bevorzugt führt, fehlen.
# Schreiben die Quellen einen Namen verschieden, gilt die klein geschriebene
# Form.
test_synonym_search_holds_synonyms_of_active_species() {
    create_synonym_search_db
    rebuild_fts
    assert_status 0
    assert_eq "Amphiprion bicolor → discere:species:1
Amphiprion communis → discere:species:2
Amphiprion communis → discere:species:3" "$(synonym_rows)" "Synonyme"
}

# MATCH sucht im Namen, auch nach einem Epitheton oder Präfix, nicht in der
# ID der Art.
test_synonym_search_matches_epithet_not_species_id() {
    create_synonym_search_db
    rebuild_fts
    assert_status 0
    assert_eq "discere:species:2
discere:species:3" "$(species_matching 'communis')" "Epitheton"
    assert_eq "discere:species:1" "$(species_matching 'bico*')" "Präfix"
    assert_eq "" "$(species_matching 'discere')" "ID"
}
