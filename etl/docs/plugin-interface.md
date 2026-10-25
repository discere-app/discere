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

## Aufruf-Schnittstelle

Jedes Plugin versteht dieselben gemeinsamen Flags, ohne Ausnahme:

| Flag | Bedeutung |
|------|-----------|
| `--db <path>` | Ziel-Datenbank, Pflicht; ersatzweise die Umgebungsvariable `DB_PATH` |
| `--no-download` | Nichts laden, die Dateien im eigenen Cache verwenden |
| `--keep` | Selbst geladene Dateien nach dem Import behalten |
| `--help` | Kopfkommentar des Plugins ausgeben |

- Herunterladen ist der Default: Ohne `--no-download` lädt ein Plugin seine
  Quelldaten in seinen Cache (`plugins/<name>/cache/`) und löscht sie nach
  dem Import, außer mit `--keep`. Ein Plugin, das nichts lädt (`curated`),
  nimmt `--no-download` und `--keep` still hin.
- Eigene Einstellungen eines Plugins (Version, lokale Pfade) kommen über
  Umgebungsvariablen mit dem Quellenschlüssel als Präfix (`FISHBASE_DIR`,
  `INAT_TAXA_FILE`) und für den Direktaufruf zusätzlich über eigene Flags mit
  Wert; das Flag hat Vorrang. `build.sh` gibt nur die gemeinsamen Flags
  weiter, die Umgebung erbt jedes Plugin — das Präfix hält die Variablen der
  Plugins auseinander.
- Ein ausdrücklich angegebener lokaler Pfad, ob Flag oder Umgebungsvariable,
  wird nur gelesen: kein Download, kein Löschen. Ein Plugin löscht nur, was
  es selbst in seinen Cache geladen hat.
- Ein unbekanntes Flag bricht ab. Ein Tippfehler wie `--no-dowload` würde
  sonst still laden und danach löschen.

Gelesen werden alle Flags von `plugin_parse_args` in `core/plugin_api.sh`;
kein Plugin parst sie selbst. Das Plugin nennt seine eigenen Flags samt der
Variablen, die sie setzen, und gibt danach seinen lokalen Pfad an
`plugin_skip_download_for_local_path` (aus
[`plugins/_template/import.sh`](../plugins/_template/import.sh)):

```bash
EXAMPLE_DATA_DIR="${EXAMPLE_DATA_DIR:-}"
plugin_parse_args --data-dir=EXAMPLE_DATA_DIR -- "$@"
plugin_skip_download_for_local_path "$EXAMPLE_DATA_DIR"
DATA_DIR="${EXAMPLE_DATA_DIR:-$PLUGIN_DIR/cache}"
```

Danach gelten `DB_PATH`, `DOWNLOAD` (`true`, mit `--no-download` `false`)
und `KEEP_FILES` (mit `--keep` `true`). Der Header des Plugins nennt nur seine
eigenen Flags und Umgebungsvariablen, `plugin.yaml` ebenso (`flags:`/`env:`,
reine Dokumentation).

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
  - muss dem Muster `[a-z0-9][a-z0-9_-]*` entsprechen und gleich dem
    Verzeichnisnamen sein

Optional:

```yaml
depends_on_sources:
  - fishbase
optional: true
placement_priority: 10
```

- `depends_on_sources`
  - Blockliste der Quellenschlüssel, gegen deren Daten das Plugin abgleicht;
    bestimmt die Reihenfolge im Build
- `optional`
  - `true`: Die Quelle ergänzt nur, `--no-enrich` überspringt sie samt den
    Quellen, die von ihr abhängen. Fehlt das Feld, gilt `false`.
- `placement_priority`
  - ganze Zahl, kleiner = gewichtiger; nur für Quellen, die Einordnungen
    liefern, und je Build eindeutig

Was `build.sh` daraus macht, steht in
[`plugin-system.md`](plugin-system.md#abhängigkeiten-reihenfolge-und-rang).

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

### Manifest

- `plugin_manifest_get "$PLUGIN_MANIFEST_PATH" "version"`
  - liest einen skalaren Wert (`key: value`) eines Schlüssels ohne Einrückung;
    gleichnamige verschachtelte Schlüssel (etwa unter `env:`) zählen nicht
- `plugin_manifest_list "$PLUGIN_MANIFEST_PATH" "depends_on_sources"`
  - gibt die Einträge einer Blockliste aus, einen pro Zeile, ohne Kommentare
    und Anführungszeichen
  - eine leere oder fehlende Liste ergibt keine Ausgabe
  - Inline-Listen (`[a, b]`) und leere Einträge werden nicht unterstützt und
    brechen mit `plugin_fail` ab

### Logging

- `plugin_log "Nachricht"`
  - stderr-Log mit `[<source>]`
- `plugin_warn "Nachricht"`
  - Warnung auf stderr
- `plugin_fail "Nachricht"`
  - Fehler auf stderr und `exit 1`

### CLI / Setup

- `plugin_parse_args [<flag>=<VARIABLE> …] -- "$@"`
  - liest die [Aufruf-Schnittstelle](#aufruf-schnittstelle)
- `plugin_skip_download_for_local_path "$EXAMPLE_DATA_DIR"`
  - setzt `DOWNLOAD=false`, wenn der Pfad nicht leer ist: Ein angegebener
    lokaler Pfad wird nur gelesen
- `plugin_print_help "$0"`
  - druckt den Kopfkommentar zwischen den ersten beiden `# ===`-Linien als
    Hilfe; `plugin_parse_args` ruft es für `--help` auf
- `plugin_print_help_from_header "$0" 2 20`
  - druckt die angegebenen Zeilen eines Scripts als Hilfe
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

### Build-Bericht

- `plugin_report < eintraege.tsv`
  - liest je Zeile tabgetrennt Kategorie, Schlüssel, Name, Detail und hängt
    sie mit der Quelle an `$DISCERE_REPORT_DIR/<source>.tsv` an
  - `build.sh` setzt `DISCERE_REPORT_DIR`; ohne die Variable werden die
    Einträge nur gezählt und im Log gemeldet

### Abgleich

Nach `source "$PLUGIN_CORE_DIR/match.sh"`:

- `match_records "$DB_PATH" eingabe.tsv ergebnis.tsv`
  - Eingabe: TSV mit Kopfzeile `record_key`, `rank`, `name`; Rang
    `species`, `genus`, `family`, `order` oder `class`
  - Ergebnis: TSV mit `record_key`, `rank`, `name`, `entity_id`, `status`
    (`matched`/`none`/`ambiguous`), `matched_by` (`name`/`synonym`), `detail`
  - schreibt `none` und `ambiguous` in den Build-Bericht
  - die TSVs tragen kein Quoting: Ein `"` gehört zum Namen

### Source-Metadaten

- `plugin_write_source_metadata "$DB_PATH" "$PLUGIN_SQL_DIR/source.sql" "$SOURCE_VERSION"`
  - rendert `source.sql` mit `${VERSION}` und `${NOW}`
  - schreibt zusätzlich den technischen Versionswert in `metadata`

---

## Verantwortung der Plugin-Autoren

Die Plugin-API nimmt wiederkehrende Infrastrukturarbeit ab. Sie ersetzt nicht
den datenquellenspezifischen Teil des Plugins.

Plugin-Autoren bleiben verantwortlich für:

- eigene Flags, Umgebungsvariablen und Defaults für ihre Quelle
- Download-Logik
- `sql/export.sql`, sofern die Quelle Parquets per DuckDB exportiert
- SQLite-Import
- plugin-spezifische Schnellvalidierung

---

## Empfohlene Struktur

```text
plugins/<name>/
  plugin.yaml
  import.sh
  sql/
    source.sql
    export.sql   # nur parquet-basierte Quellen
```

Als Ausgangspunkt dient [`plugins/_template`](../plugins/_template).
