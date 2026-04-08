# Neues Plugin schreiben

Schritt-für-Schritt-Anleitung für neue Plugins im Discere ETL.

---

## Voraussetzungen

- [`duckdb`](https://duckdb.org/docs/installation/) CLI installiert
- `sqlite3` CLI verfügbar
- Grundkenntnisse in Bash und SQL

---

## Schritt 1 — Verzeichnis anlegen

```bash
mkdir -p plugins/<mein-plugin>/sql
cp -r plugins/_template/. plugins/<mein-plugin>/
```

---

## Schritt 2 — plugin.yaml ausfüllen

```yaml
name: mein-plugin
version: 1          # Manifest-Version
source: mein-plugin   # wird als external_source in der DB gespeichert
                      # muss über alle Plugins eindeutig sein

provides:
  - species
  - pictures

requires:
  - duckdb
  - sqlite3
```

---

## Schritt 3 — export.sql schreiben (DuckDB)

`sql/export.sql` läuft in einer einzigen DuckDB-Session und schreibt CSVs in `${EXPORT_DIR}`.

**Wichtig:** Immer `discere_uuid()` für IDs verwenden — nie selbst konstruieren.

```sql
-- Makros zuerst definieren (immer gleich, aus _template kopieren)
CREATE OR REPLACE MACRO stable_uuid(input) AS ...;
CREATE OR REPLACE MACRO discere_uuid(source, entity, external_id) AS ...;

-- Dann die eigentlichen Queries
CREATE TEMP TABLE t_species AS
SELECT
    discere_uuid('mein-plugin', 'species', s.id)  AS id,
    CAST(s.id AS VARCHAR)                          AS external_id,
    'mein-plugin'                                  AS external_source,
    s.scientific_name                              AS name,
    s.name_de                                      AS common_name_de,
    s.name_en                                      AS common_name_en,
    NULL                                           AS common_name_fr,
    NULL                                           AS common_name_es,
    s.avg_length                                   AS common_length,
    NULL                                           AS common_weight,
    NULL                                           AS genus,   -- oder FK auf t_genera
    'active'                                       AS status,
    NULL                                           AS deprecated_at
FROM read_parquet('${DATA_DIR}/species.parquet') s;

COPY t_species TO '${EXPORT_DIR}/species.csv' (FORMAT csv, HEADER true);
```

Die Reihenfolge muss der FK-Hierarchie folgen:

```
classes → orders → families → genera → species → pictures
```

Jede Tabelle als `TEMP TABLE` anlegen damit nachfolgende Tabellen joinen können.

---

## Schritt 4 — import.sh schreiben

Aus `_template/import.sh` kopieren und anpassen:

1. `core/plugin_api.sh` sourcen
2. `plugin_init "$PLUGIN_DIR"` aufrufen
3. Download-Logik implementieren (oder weglassen wenn kein Download nötig)
4. `DATA_DIR` oder andere quellspezifische Pfade definieren
5. `export_to_csv()` — Datenpfade in den Sed-Ersetzungen ergänzen
6. `import_to_sqlite()` — SQLite-Import-Script schreiben (analog fishbase)
7. `validate()` — Plugin-spezifische Schnellprüfung

Zusätzlich `sql/source.sql` anpassen:

- `id` muss mit `plugin.yaml:source` übereinstimmen
- Zitierung, URL, Lizenz und `display_order` pflegen
- `${VERSION}` und `${NOW}` als Platzhalter stehen lassen

Minimaler Start:

```bash
set -Eeuo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../core/plugin_api.sh
source "$PLUGIN_DIR/../../core/plugin_api.sh"
plugin_init "$PLUGIN_DIR"
```

Wichtige Helper aus der Plugin-API:

- `plugin_require_db_path "$DB_PATH"`
- `plugin_require_command duckdb sqlite3`
- `plugin_write_source_metadata "$DB_PATH" "$PLUGIN_SQL_DIR/source.sql" "$SOURCE_VERSION"`
- `plugin_validate_source_entry_exists "$DB_PATH"`
- `plugin_validate_min_count ...`

```bash
chmod +x plugins/<mein-plugin>/import.sh
```

---

## Schritt 5 — Lokal testen

```bash
# Leere DB erstellen
./core/create_db.sh --output /tmp/test.db --force

# Plugin einzeln ausführen
./plugins/<mein-plugin>/import.sh --db /tmp/test.db --no-download

# Daten prüfen
sqlite3 /tmp/test.db "SELECT COUNT(*) FROM species WHERE external_source = 'mein-plugin';"
sqlite3 /tmp/test.db "SELECT * FROM metadata;"

# UUID-Format prüfen
sqlite3 /tmp/test.db "SELECT COUNT(*) FROM species WHERE id NOT GLOB 'discere:*_*:*';"
# Erwartet: 0
```

---

## Schritt 6 — In den Build einbinden

```bash
# Nur das neue Plugin
./build.sh --plugin mein-plugin --no-download --force

# Alle Plugins
./build.sh --force
```

---

## Häufige Fehler

**UUIDs stimmen nicht mit FKs überein**
Sicherstellen dass Parent-Tabellen als `TEMP TABLE` in derselben DuckDB-Session angelegt sind und Children per `LEFT JOIN` auf diese joinen — nicht über `discere_uuid()` des externen IDs neu berechnen.

**`external_source` stimmt nicht mit `plugin.yaml:source` überein**
Beide müssen identisch sein. Sonst findet `clear_existing_data()` nichts zu löschen und der Import ist nicht idempotent.

**Plugin läuft im Build nicht**
`validate_plugin.sh` prüft Struktur und Ausführbarkeit. Checklist:
- `plugin.yaml` vorhanden?
- `plugin.yaml` enthält `name`, `version`, `source`?
- `import.sh` vorhanden und `chmod +x` gesetzt?
- `sql/export.sql` vorhanden?
- `sql/source.sql` vorhanden?

**UUID-Validierung schlägt fehl**
`validate.sql` prüft nach dem Import ob alle IDs dem Format `discere:*_*:*` entsprechen. Häufige Ursachen:
- `discere_uuid()` Makro nicht verwendet
- `source` oder `entity` enthält ein Leerzeichen
- `external_id` ist NULL

Weitere Details zur gemeinsamen Shell-Schnittstelle stehen in
[`plugin-interface.md`](plugin-interface.md).
