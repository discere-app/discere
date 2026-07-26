# Discere ETL

Baut `discere_reference.db` aus Fischdaten-Quellen.

---

## Schnellstart

```bash
./build.sh
```

Findet alle Plugins automatisch, lädt Daten herunter und räumt danach auf.

---

## Architektur

```
build.sh                       ← Orchestrator
├── core/
│   ├── create_db.sh           ← Erstellt leere DB mit Schema
│   ├── plugin_api.sh          ← Gemeinsame Shell-API für Plugins
│   └── sql/
│       ├── schema.sql         ← Tabellen, Indexes, FTS
│       ├── rebuild_fts.sql    ← FTS rebuild nach allen Plugins
│       └── validate.sql       ← Mindest-Zeilenzahlen
└── plugins/
    └── fishbase/
        ├── import.sh          ← FishBase-Import
        └── sql/
            └── export.sql     ← DuckDB: Parquet → CSV (eine Session)
```

### Verantwortlichkeiten

**`build.sh`** — kennt nur die Reihenfolge der Stages. Übergibt den DB-Pfad an jedes Plugin.

**`core/create_db.sh`** — erstellt die leere DB, legt Schema an. Gibt den DB-Pfad auf stdout aus.

**`plugins/*/import.sh`** — kennt nur seine eigene Datenquelle. Kein Schema, nur Daten. Logs auf stderr.
Sie sourcen idealerweise `core/plugin_api.sh`, damit Logging, Manifest-Parsing und
Source-Metadaten nicht pro Plugin neu geschrieben werden müssen.

### Pipeline-Stages

| Stage | Script | Aufgabe |
|-------|--------|---------|
| 01 | `core/create_db.sh` | Leere DB + Schema |
| 02 | `plugins/*/import.sh` | Daten laden, transformieren, importieren |
| 03 | `core/sql/rebuild_fts.sql` | FTS rebuild über alle Daten (nach allen Plugins) |
| 04 | `core/sql/validate.sql` | Mindestzahlen prüfen |

---

## Verwendung

```bash
# Standardfall: alle Plugins, download + cleanup
./build.sh

# Parquets behalten
./build.sh --keep

# Kein Download — lokale Dateien verwenden
./build.sh --no-download --fishbase-dir ~/data/fishbase/parquet

# Nur ein Plugin
./build.sh --plugin fishbase

# Andere Version
./build.sh --version v24.07

# Eigener Output-Pfad
./build.sh --output ~/dev/discere.db

# Bestehende DB überschreiben
./build.sh --force
```

### Flags

| Flag | Beschreibung |
|------|-------------|
| `--plugin <n>` | Plugin explizit angeben (wiederholbar). Ohne Flag: alle Plugins in `plugins/` |
| `--output <path>` | Ziel-Datenbank |
| `--force` | Bestehende DB überschreiben |
| `--download` | Download explizit aktivieren (ist Default wenn kein Flag gesetzt) |
| `--no-download` | Download deaktivieren — lokale Dateien verwenden |
| `--keep` | Heruntergeladene Dateien behalten |
| `--version <v25.04>` | An alle Plugins weitergegeben |
| `--fishbase-dir <path>` | Nur an fishbase-Plugin weitergegeben |

### Umgebungsvariablen

Flags können als Umgebungsvariablen gesetzt werden:

```bash
export OUTPUT_DB=~/dev/discere/assets/database/discere_reference.db
./build.sh
```

Oder inline:

```bash
OUTPUT_DB=~/dev/discere/assets/database/discere_reference.db ./build.sh
```

Flags haben Vorrang vor Umgebungsvariablen.

| Umgebungsvariable | Flag |
|-------------------|------|
| `OUTPUT_DB` | `--output` |
| `FISHBASE_VERSION` | `--version` |
| `FISHBASE_DIR` | `--fishbase-dir` |

---

## Schema

```
classes ──< orders ──< families ──< genera ──< species ──< pictures
                                                            metadata (key/value)
```

Alle Tabellen ausser `pictures` und `metadata`:

| Spalte | Typ | Beschreibung |
|--------|-----|-------------|
| `id` | TEXT PK | Deterministische interne ID im Format `discere:<source>_<entity>:<external_id>` |
| `external_id` | TEXT NOT NULL | ID in der Originalquelle (z.B. `speccode`) |
| `external_source` | TEXT NOT NULL | Quelle (z.B. `fishbase`) — kein Default, explizit setzen |

`external_id` + `external_source` bilden einen Unique Constraint — jede Quell-Entität existiert genau einmal.

**ID-Generierung:** Alle Taxonomie-IDs werden deterministisch über `discere_uuid(source, entity, external_id)` erzeugt. Parents (classes → orders → families → genera → species) werden zuerst in temporäre Tabellen geladen; Children joinen auf diese um dieselben IDs als FKs zu übernehmen. Dadurch bleiben interne IDs über ETL-Runs stabil, solange Quelle und externe ID gleich bleiben.

**`metadata`** — eine Zeile pro importierter Quelle:

```
key          | value
fishbase     | v25.04
sealifebase  | v25.04
```

---

## Neues Plugin erstellen

Ein Plugin ist ein `import.sh` in `plugins/<n>/`. Protokoll:

- `plugin.yaml` mit `name`, `version`, `source` anlegen
- `core/plugin_api.sh` sourcen und `plugin_init "$PLUGIN_DIR"` aufrufen
- `--db <path>` als Pflichtflag entgegennehmen
- Logs auf **stderr**, nichts auf stdout
- **Kein** `CREATE TABLE` — Schema gehört in `core/`
- Idempotent: eigene Daten vor dem Import löschen (`WHERE external_source = '<n>'`)
- `metadata` nach erfolgreichem Import beschreiben
- UUIDs für FKs via DuckDB-Session-JOIN auflösen (siehe `plugins/fishbase/sql/export.sql`)

Weiterführend:

- [`docs/plugin-system.md`](docs/plugin-system.md)
- [`docs/plugin-interface.md`](docs/plugin-interface.md)
- [`docs/how-to-write-plugin.md`](docs/how-to-write-plugin.md)

---

## Flutter-Integration

`discere_reference.db` wird nicht mehr in die App gebundelt (zu gross), sondern
zur Laufzeit heruntergeladen — siehe `FLUTTER_INTEGRATION.md` für die
Detail-Erklärung und `../misc/tasks/reference-db-target-architecture.md` für
das Zielbild. Zwei zusätzliche Skripte hängen an einem lokal gebauten
`discere_reference.db`:

```bash
# Maintainer-only: gebaute DB als Release veröffentlichen (braucht CODEBERG_TOKEN)
CODEBERG_TOKEN=... ./publish_release.sh --version <n> --schema-version <n>

# Kleine, kuratierte Test-Fixture aus einer gebauten DB extrahieren
# (Output: ../test/fixtures/discere_reference_test.db, von Repository- und
# Integrationstests verwendet)
./scripts/build_test_fixture.sh
```

Neue Art in einem Test gebraucht, die noch nicht in der Fixture ist? In
`scripts/test_fixture_species.txt` ergänzen und `build_test_fixture.sh` neu
laufen lassen.

---

## Voraussetzungen

- [`duckdb`](https://duckdb.org/docs/installation/) CLI
- `sqlite3` CLI
- `curl` (nur bei `--download`)

---

## Hinweise

- `pictures`-IDs sind UUIDs ohne stabilen externen Schlüssel — Picture-IDs nicht in User-Daten referenzieren. Stattdessen `external_id` + `external_source` der zugehörigen Species speichern.
- Externe Mappings in andere Systeme (z.B. iNaturalist) gehören in `entity_external_ids`. Für taxonomische Namens-Enrichments dürfen dort auch normalisierte Schlüssel wie `genus:barbus` oder `family:cyprinidae` verwendet werden, wenn die Laufzeit mit name-basierten Keys arbeitet.
- FTS verwendet FTS4 (nicht FTS5 — im sqflite SQLite-Build auf iOS/Android nicht zuverlässig verfügbar). Rebuild läuft automatisch nach allen Plugins in Stage 03.
- `species` verwendet LEFT JOIN mit `comnames` — alle Spezies werden importiert, auch ohne Common Name.
- FishBase und SeaLifeBase haben disjunkte Species aber potenzielle Überlappungen in `families` und `genera` (Homonyme). Diese sind keine echten Duplikate — gleicher Name, biologisch verschiedene Entitäten. Jede Quelle bleibt isoliert mit eigenem `external_source`.
