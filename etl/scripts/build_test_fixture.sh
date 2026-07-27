#!/usr/bin/env bash
# =============================================================================
# build_test_fixture.sh — Baut die kleine Reference-DB-Fixture für Tests
#
# Filtert eine lokal gebaute Voll-DB (etl/build.sh) auf eine kuratierte
# Artenliste (test_fixture_species.txt) herunter — inkl. vollständiger
# Taxonomie-Ahnenkette, Common Names, wissenschaftlicher Namen/Synonyme,
# Bilder und Traits/Verbreitungsdaten für genau diese Arten. FTS-Indexe und
# species_name_lookup werden danach über die bestehenden ETL-SQL-Skripte neu
# aufgebaut (core/sql/rebuild_fts.sql, core/sql/rebuild_lookup.sql).
#
# Ergebnis wird nach test/fixtures/discere_reference_test.db committet und von
# test/catalog/repository/species_repository_*_test.dart sowie (als
# gebündeltes Flutter-Asset) integration_test/test_utils.dart verwendet.
#
# Usage:
#   ./etl/scripts/build_test_fixture.sh
#   ./etl/scripts/build_test_fixture.sh --source /pfad/zur/vollen.db
#
# Flags:
#   --source <path>       Volle Reference-DB (Default: assets/database/discere_reference.db)
#   --output <path>       Ziel-Pfad (Default: test/fixtures/discere_reference_test.db)
#   --species-file <path> Artenliste (Default: etl/scripts/test_fixture_species.txt)
#
# Wenn Tests eine neue Art brauchen: Namen in test_fixture_species.txt
# ergänzen, dieses Skript neu laufen lassen, Diff committen.
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SOURCE_DB="$REPO_ROOT/assets/database/discere_reference.db"
OUTPUT_DB="$REPO_ROOT/test/fixtures/discere_reference_test.db"
SPECIES_FILE="$SCRIPT_DIR/test_fixture_species.txt"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) SOURCE_DB="$2"; shift ;;
        --output) OUTPUT_DB="$2"; shift ;;
        --species-file) SPECIES_FILE="$2"; shift ;;
        --help|-h)
            sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "[WARN] [build_test_fixture] Unbekanntes Argument: $1" >&2 ;;
    esac
    shift
done

log()  { echo "[$(date '+%H:%M:%S')] [build_test_fixture] $*" >&2; }
fail() { echo "[ERROR] [build_test_fixture] $*" >&2; exit 1; }

[[ -f "$SOURCE_DB" ]] || fail "Quelle nicht gefunden: $SOURCE_DB (erst ./etl/build.sh laufen lassen)"
[[ -f "$SPECIES_FILE" ]] || fail "Artenliste nicht gefunden: $SPECIES_FILE"

mkdir -p "$(dirname "$OUTPUT_DB")"
rm -f "$OUTPUT_DB"

log "Kopiere $SOURCE_DB -> $OUTPUT_DB"
cp "$SOURCE_DB" "$OUTPUT_DB"

# Normalisierte Namen (lowercase) aus der Artenliste, Kommentare/Leerzeilen raus.
NORMALIZED_NAMES=$(grep -v '^#' "$SPECIES_FILE" | grep -v '^[[:space:]]*$' | tr '[:upper:]' '[:lower:]' | sed "s/'/''/g")
NAME_COUNT=$(echo "$NORMALIZED_NAMES" | wc -l | tr -d ' ')
log "Ziel: $NAME_COUNT Arten aus $SPECIES_FILE"

VALUES_CLAUSE=$(echo "$NORMALIZED_NAMES" | sed "s/.*/('&')/" | paste -sd, -)

# Fail loudly if a curated name didn't resolve, instead of silently shipping
# a smaller fixture than the test list expects.
RESOLVED_COUNT=$(sqlite3 "$OUTPUT_DB" "
  SELECT COUNT(DISTINCT t.normalized_name)
  FROM (SELECT column1 AS normalized_name FROM (VALUES $VALUES_CLAUSE)) t
  JOIN species_scientific_names ssn ON ssn.normalized_name = t.normalized_name;
")
if [[ "$RESOLVED_COUNT" -ne "$NAME_COUNT" ]]; then
    log "Nicht aufgelöste Namen:"
    sqlite3 "$OUTPUT_DB" "
      SELECT t.normalized_name
      FROM (SELECT column1 AS normalized_name FROM (VALUES $VALUES_CLAUSE)) t
      LEFT JOIN species_scientific_names ssn ON ssn.normalized_name = t.normalized_name
      WHERE ssn.normalized_name IS NULL;
    " >&2
    fail "Nur $RESOLVED_COUNT von $NAME_COUNT kuratierten Arten in $SOURCE_DB gefunden."
fi

sqlite3 "$OUTPUT_DB" <<SQL
PRAGMA foreign_keys = OFF;

CREATE TEMP TABLE _fixture_target_names(normalized_name TEXT PRIMARY KEY);
INSERT INTO _fixture_target_names(normalized_name) VALUES $VALUES_CLAUSE;

CREATE TEMP TABLE _fixture_species_ids(id TEXT PRIMARY KEY);
INSERT INTO _fixture_species_ids(id)
SELECT DISTINCT ssn.species_id
FROM species_scientific_names ssn
JOIN _fixture_target_names t ON t.normalized_name = ssn.normalized_name;

CREATE TEMP TABLE _fixture_genus_ids(id TEXT PRIMARY KEY);
INSERT INTO _fixture_genus_ids(id)
SELECT DISTINCT s.genus FROM species s
JOIN _fixture_species_ids f ON f.id = s.id
WHERE s.genus IS NOT NULL;

CREATE TEMP TABLE _fixture_family_ids(id TEXT PRIMARY KEY);
INSERT INTO _fixture_family_ids(id)
SELECT DISTINCT g.family FROM genera g
JOIN _fixture_genus_ids f ON f.id = g.id
WHERE g.family IS NOT NULL;

CREATE TEMP TABLE _fixture_order_ids(id TEXT PRIMARY KEY);
INSERT INTO _fixture_order_ids(id)
SELECT DISTINCT fam."order" FROM families fam
JOIN _fixture_family_ids f ON f.id = fam.id
WHERE fam."order" IS NOT NULL;

CREATE TEMP TABLE _fixture_class_ids(id TEXT PRIMARY KEY);
INSERT INTO _fixture_class_ids(id)
SELECT DISTINCT o.class FROM orders o
JOIN _fixture_order_ids f ON f.id = o.id
WHERE o.class IS NOT NULL;

-- All surviving taxonomic entity ids (species + full ancestor chain),
-- used to filter the entity-keyed side tables below.
CREATE TEMP TABLE _fixture_entity_ids(id TEXT PRIMARY KEY);
INSERT INTO _fixture_entity_ids(id) SELECT id FROM _fixture_species_ids;
INSERT INTO _fixture_entity_ids(id) SELECT id FROM _fixture_genus_ids;
INSERT INTO _fixture_entity_ids(id) SELECT id FROM _fixture_family_ids;
INSERT INTO _fixture_entity_ids(id) SELECT id FROM _fixture_order_ids;
INSERT INTO _fixture_entity_ids(id) SELECT id FROM _fixture_class_ids;

DELETE FROM species WHERE id NOT IN (SELECT id FROM _fixture_species_ids);
DELETE FROM genera  WHERE id NOT IN (SELECT id FROM _fixture_genus_ids);
DELETE FROM families WHERE id NOT IN (SELECT id FROM _fixture_family_ids);
DELETE FROM orders   WHERE id NOT IN (SELECT id FROM _fixture_order_ids);
DELETE FROM classes  WHERE id NOT IN (SELECT id FROM _fixture_class_ids);

DELETE FROM species_scientific_names
  WHERE species_id NOT IN (SELECT id FROM _fixture_species_ids);
DELETE FROM common_names
  WHERE entity_id NOT IN (SELECT id FROM _fixture_entity_ids);
DELETE FROM taxonomy_traits
  WHERE entity_id NOT IN (SELECT id FROM _fixture_entity_ids);
DELETE FROM taxonomy_distribution_regions
  WHERE entity_id NOT IN (SELECT id FROM _fixture_species_ids);
DELETE FROM entity_external_ids
  WHERE entity_id NOT IN (SELECT id FROM _fixture_entity_ids);
DELETE FROM pictures
  WHERE species NOT IN (SELECT id FROM _fixture_species_ids);

DROP TABLE _fixture_target_names;
DROP TABLE _fixture_species_ids;
DROP TABLE _fixture_genus_ids;
DROP TABLE _fixture_family_ids;
DROP TABLE _fixture_order_ids;
DROP TABLE _fixture_class_ids;
DROP TABLE _fixture_entity_ids;
SQL

log "Baue species_name_lookup neu auf"
sqlite3 "$OUTPUT_DB" < "$REPO_ROOT/etl/core/sql/rebuild_lookup.sql"

log "Baue FTS-Indexe neu auf"
sqlite3 "$OUTPUT_DB" < "$REPO_ROOT/etl/core/sql/rebuild_fts.sql"

log "VACUUM"
sqlite3 "$OUTPUT_DB" "VACUUM;"

SPECIES_COUNT=$(sqlite3 "$OUTPUT_DB" "SELECT COUNT(*) FROM species;")
SIZE=$(du -h "$OUTPUT_DB" | cut -f1)
log "Fertig: $OUTPUT_DB ($SPECIES_COUNT Arten, $SIZE)"
