# Plugin Interface

Die gemeinsame Shell-Schnittstelle für Discere-ETL-Plugins liegt in
[`core/plugin_api.sh`](../core/plugin_api.sh).

Ein Plugin soll diese Datei sourcen statt Logging, Manifest-Parsing und
Source-Metadaten in jedem `import.sh` neu zu implementieren.

---

## Minimaler Einstieg

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../core/plugin_api.sh
source "$PLUGIN_DIR/../../core/plugin_api.sh"
plugin_init "$PLUGIN_DIR"
```

Danach stehen Manifest-Daten und Helper-Funktionen zur Verfügung.

---

## Manifest-Kontrakt

Jedes Plugin braucht ein `plugin.yaml` mit mindestens:

```yaml
name: my-plugin
version: 1
source: my-plugin
```

- `name`
  - Anzeigename des Plugins
- `version`
  - Version des Plugin-Manifests, nicht der Quelldaten
- `source`
  - eindeutiger technischer Schlüssel
  - wird als `external_source` und `sources.id` verwendet
  - muss dem Muster `[a-z0-9][a-z0-9_-]*` entsprechen

---

## Exportierte Variablen

Nach `plugin_init "$PLUGIN_DIR"` sind folgende Variablen verfügbar:

- `PLUGIN_DIR`
  - absolutes Plugin-Verzeichnis
- `PLUGIN_ETL_DIR`
  - ETL-Wurzelverzeichnis
- `PLUGIN_CORE_DIR`
  - Pfad zu `core/`
- `PLUGIN_SQL_DIR`
  - Pfad zu `sql/`
- `PLUGIN_MANIFEST_PATH`
  - Pfad zu `plugin.yaml`
- `PLUGIN_NAME`
  - Wert aus `plugin.yaml:name`
- `PLUGIN_SOURCE`
  - Wert aus `plugin.yaml:source`
- `PLUGIN_MANIFEST_VERSION`
  - Wert aus `plugin.yaml:version`

---

## Helper-Funktionen

### Logging

- `plugin_log "Nachricht"`
  - stderr-Log mit `[<source>]`
- `plugin_warn "Nachricht"`
  - Warnung auf stderr
- `plugin_fail "Nachricht"`
  - Fehler auf stderr und `exit 1`

### CLI / Setup

- `plugin_print_help_from_header "$0" 2 20`
  - druckt den Header-Kommentar eines Scripts als Hilfe
- `plugin_cleanup_dir "$EXPORT_DIR"`
  - löscht ein temporäres Verzeichnis

### Validierung

- `plugin_require_db_path "$DB_PATH"`
  - prüft `--db`
- `plugin_require_command duckdb sqlite3`
  - prüft CLI-Abhängigkeiten
- `plugin_validate_min_count "$DB_PATH" "species" "external_source='my-plugin'" 1 "Species"`
  - einfache Mindestzahl-Prüfung
- `plugin_validate_source_entry_exists "$DB_PATH"`
  - prüft ob `source.sql` erfolgreich einen `sources`-Eintrag geschrieben hat

### Source-Metadaten

- `plugin_write_source_metadata "$DB_PATH" "$PLUGIN_SQL_DIR/source.sql" "$SOURCE_VERSION"`
  - rendert `source.sql` mit `${VERSION}` und `${NOW}`
  - schreibt zusätzlich den technischen Versionswert in `metadata`

---

## Verantwortung der Plugin-Autoren

Die Plugin-API nimmt wiederkehrende Infrastrukturarbeit ab. Sie ersetzt nicht
den datenquellenspezifischen Teil des Plugins.

Plugin-Autoren bleiben verantwortlich für:

- Argumente und Defaults für ihre Quelle
- Download-Logik
- `sql/export.sql`
- SQLite-Import
- plugin-spezifische Schnellvalidierung

---

## Empfohlene Struktur

```text
plugins/<name>/
  plugin.yaml
  import.sh
  sql/
    export.sql
    source.sql
```

Als Ausgangspunkt dient [`plugins/_template`](../plugins/_template).
