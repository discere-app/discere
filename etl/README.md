# Discere ETL

Baut `discere_reference.db` aus Fischdaten-Quellen.

## Schnellstart

```bash
./build.sh
```

---

## Architektur

```
build.sh                       ← Orchestrator
├── core/
│   ├── create_db.sh           ← Erstellt leere DB mit Schema
│   └── sql/
│       ├── schema.sql         ← Tabellen, Indexes, FTS
│       └── validate.sql       ← Mindest-Zeilenzahlen
└── plugins/
    └── fishbase/
        ├── import.sh          ← FishBase-Import
        └── sql/               ← DuckDB SELECT queries
            ├── 01_classes.sql
            ├── 02_orders.sql
            ├── 03_families.sql
            ├── 04_genera.sql
            ├── 05_species.sql
            └── 06_pictures.sql
```

### Verantwortlichkeiten

**`build.sh`** kennt nur welche Scripts in welcher Reihenfolge laufen. Er übergibt den DB-Pfad an jedes Plugin und führt am Ende die zentrale Validierung aus.

**`core/create_db.sh`** erstellt die leere Datenbank und legt das Schema an. Gibt den DB-Pfad auf stdout aus — so kann `build.sh` ihn ohne Umwege weitergeben.

**`plugins/*/import.sh`** kennt nur seine eigene Datenquelle. Es darf nichts am Schema ändern — nur Daten in bestehende Tabellen einfügen. Schreibt Logs auf stderr, nichts auf stdout.

---

## Verwendung

```bash
# Standardfall: alle Plugins auto-discover, download + cleanup
./build.sh

# Parquets behalten (kein Cleanup nach Import)
./build.sh --keep

# Lokale Parquets — kein Download
./build.sh --no-download --fishbase-dir ~/data/fishbase/parquet

# Nur ein bestimmtes Plugin
./build.sh --plugin fishbase

# Andere Version
./build.sh --version v24.07

# Eigener Output-Pfad
./build.sh --output ~/dev/discere.db

# Bestehende DB überschreiben
./build.sh --force
```

### Flags

| Flag                    | Beschreibung                                                                        |
|-------------------------|-------------------------------------------------------------------------------------|
| `--plugin <n>`          | Plugin explizit angeben (wiederholbar). Ohne Flag: alle Plugins in `plugins/` verwendet |
| `--output <path>`       | Ziel-Datenbank                                                                      |
| `--force`               | Bestehende DB überschreiben                                                         |
| `--download`            | Download explizit aktivieren (ist Default wenn kein Flag gesetzt)                   |
| `--no-download`         | Download deaktivieren — lokale Dateien verwenden                                    |
| `--keep`                | Heruntergeladene Dateien nach dem Import behalten                                   |
| `--version <v25.04>`    | An alle Plugins weitergegeben                                                       |
| `--fishbase-dir <path>` | Nur an fishbase-Plugin weitergegeben                                                |

### Umgebungsvariablen

Alle Flags können als Umgebungsvariablen gesetzt werden:

```bash
export OUTPUT_DB=~/dev/discere/assets/database/discere_reference.db
./build.sh
```

Oder inline:

```bash
OUTPUT_DB=~/dev/discere/assets/database/discere_reference.db ./build.sh
```

Flags haben Vorrang vor Umgebungsvariablen.

| Umgebungsvariable  | Flag             |
|--------------------|------------------|
| `OUTPUT_DB`        | `--output`       |
| `FISHBASE_VERSION` | `--version`      |
| `FISHBASE_DIR`     | `--fishbase-dir` |

---

## Pipeline-Stages

| Stage | Script              | Aufgabe                                      |
|-------|---------------------|----------------------------------------------|
| 01    | `core/create_db.sh` | Leere DB erstellen, Schema anlegen           |
| 02    | `plugins/*/import.sh` | Daten laden, transformieren, importieren   |
| 03    | `core/sql/validate.sql` | Mindestzahlen aller Tabellen prüfen      |

---

## Schema

```
classes ──< orders ──< families ──< genera ──< species ──< pictures
                                                            metadata (key/value)
```

Alle Tabellen ausser `pictures` und `metadata`:

| Spalte            | Typ           | Beschreibung                                              |
|-------------------|---------------|-----------------------------------------------------------|
| `id`              | TEXT PK       | UUID, intern generiert                                    |
| `external_id`     | TEXT NOT NULL | ID in der Originalquelle (z.B. `speccode`)                |
| `external_source` | TEXT NOT NULL | Quelle (z.B. `fishbase`) — kein Default, explizit setzen |

**`metadata`** speichert welche Quellversion importiert wurde:

```
key          | value
fishbase     | v25.04
seacreatures | v26.02
```

---

## Neues Plugin erstellen

Ein Plugin ist ein `import.sh` in `plugins/<name>/`. Es muss folgendes Protokoll einhalten:

- `--db <path>` als Pflichtflag entgegennehmen
- Logs auf **stderr** schreiben, nichts auf stdout
- **Kein** `CREATE TABLE` — Schema ist Core-Aufgabe
- Idempotent sein: eigene Daten vor dem Import löschen (`WHERE external_source = '<name>'`)
- `metadata` nach erfolgreichem Import beschreiben

### Minimalbeispiel

```bash
# plugins/seacreatures/import.sh
#!/usr/bin/env bash
set -euo pipefail

DB_PATH=""
SOURCE_VERSION="v26.02"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)      DB_PATH="$2"; shift ;;
        --version) SOURCE_VERSION="$2"; shift ;;
        *)         echo "[WARN] Unbekanntes Argument: $1" >&2 ;;
    esac
    shift
done

[[ -n "$DB_PATH" ]] || { echo "[ERROR] --db fehlt" >&2; exit 1; }
[[ -f "$DB_PATH" ]] || { echo "[ERROR] DB nicht gefunden: $DB_PATH" >&2; exit 1; }

log() { echo "[$(date '+%H:%M:%S')] [seacreatures] $*" >&2; }

# Idempotenz
log "Lösche bestehende Daten..."
sqlite3 "$DB_PATH" "DELETE FROM species WHERE external_source = 'seacreatures';"

# Daten importieren
log "Importiere..."
sqlite3 "$DB_PATH" << SQL
INSERT INTO species (id, external_id, external_source, name, genus)
VALUES ('...', '42', 'seacreatures', 'Octopus vulgaris', '...');
SQL

# FTS rebuild
sqlite3 "$DB_PATH" "INSERT INTO species_fts(species_fts) VALUES('rebuild');"

# Metadata
sqlite3 "$DB_PATH" << SQL
INSERT INTO metadata (key, value) VALUES ('seacreatures', '${SOURCE_VERSION}')
ON CONFLICT (key) DO UPDATE SET value = excluded.value;
SQL

log "seacreatures Import abgeschlossen."
```

Dann einbinden:

```bash
./build.sh --plugin fishbase --plugin seacreatures --download
```

---

## Voraussetzungen

- [`duckdb`](https://duckdb.org/docs/installation/) CLI
- `sqlite3` CLI
- `curl` (nur bei `--download`)

---

## Hinweise

- `pictures`-IDs werden bei jedem Run neu generiert. Picture-IDs nicht in User-Daten referenzieren.
- FTS verwendet FTS4 mit `content=` Tables — keine duplizierten Daten. Rebuild wird vom Plugin automatisch ausgeführt. FTS5 ist im sqflite SQLite-Build auf iOS/Android nicht zuverlässig verfügbar.
- `species` verwendet LEFT JOIN mit `comnames` — alle Spezies werden importiert, auch ohne Common Name.
