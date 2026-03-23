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
| `id` | TEXT PK | UUID, intern generiert — stabil innerhalb einer DuckDB-Session via JOIN-Kette |
| `external_id` | TEXT NOT NULL | ID in der Originalquelle (z.B. `speccode`) |
| `external_source` | TEXT NOT NULL | Quelle (z.B. `fishbase`) — kein Default, explizit setzen |

`external_id` + `external_source` bilden einen Unique Constraint — jede Quell-Entität existiert genau einmal.

**UUID-Generierung:** Alle UUIDs werden in einer einzigen DuckDB-Session erzeugt. Parents (classes → orders → families → genera → species) werden zuerst in temporäre Tabellen geladen; Children joinen auf diese um die generierten UUIDs als FKs zu übernehmen. Damit sind PKs und FKs konsistent ohne deterministischen Schlüssel.

**`metadata`** — eine Zeile pro importierter Quelle:

```
key          | value
fishbase     | v25.04
sealifebase  | v25.04
```

---

## Neues Plugin erstellen

Ein Plugin ist ein `import.sh` in `plugins/<n>/`. Protokoll:

- `--db <path>` als Pflichtflag entgegennehmen
- Logs auf **stderr**, nichts auf stdout
- **Kein** `CREATE TABLE` — Schema gehört in `core/`
- Idempotent: eigene Daten vor dem Import löschen (`WHERE external_source = '<n>'`)
- `metadata` nach erfolgreichem Import beschreiben
- UUIDs für FKs via DuckDB-Session-JOIN auflösen (siehe `plugins/fishbase/sql/export.sql`)

---

## Voraussetzungen

- [`duckdb`](https://duckdb.org/docs/installation/) CLI
- `sqlite3` CLI
- `curl` (nur bei `--download`)

---

## Hinweise

- `pictures`-IDs sind UUIDs ohne stabilen externen Schlüssel — Picture-IDs nicht in User-Daten referenzieren. Stattdessen `external_id` + `external_source` der zugehörigen Species speichern.
- FTS verwendet FTS4 (nicht FTS5 — im sqflite SQLite-Build auf iOS/Android nicht zuverlässig verfügbar). Rebuild läuft automatisch nach allen Plugins in Stage 03.
- `species` verwendet LEFT JOIN mit `comnames` — alle Spezies werden importiert, auch ohne Common Name.
- FishBase und SeaLifeBase haben disjunkte Species aber potenzielle Überlappungen in `families` und `genera` (Homonyme). Diese sind keine echten Duplikate — gleicher Name, biologisch verschiedene Entitäten. Jede Quelle bleibt isoliert mit eigenem `external_source`.
