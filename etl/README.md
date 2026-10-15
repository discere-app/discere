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
│   ├── plugin_order.sh        ← Auswahl + Reihenfolge der Plugins
│   ├── validate_plugin.sh     ← Struktur- und Manifest-Prüfung je Plugin
│   ├── match.sh               ← Abgleich mit vorhandenen Entitäten (für Plugins)
│   ├── previous_release.sh    ← Vorgänger-Release laden (Manifest, sha256, Cache)
│   ├── identity.sh            ← Identitäts-Stage: endgültige IDs, Register, Aliase
│   ├── reference_columns.sh   ← Spalten, die auf Entitäten verweisen
│   ├── check_references.sh    ← Verweise am Ende des Builds prüfen
│   ├── report_summary.sh      ← Zusammenfassung des Build-Berichts
│   └── sql/
│       ├── schema.sql         ← Tabellen, Indexes, FTS
│       ├── match.sql          ← Regeln des Abgleichs
│       ├── identity_*.sql     ← Schritte der Identitäts-Stage
│       ├── rebuild_fts.sql    ← FTS rebuild nach allen Plugins
│       └── validate.sql       ← Mindest-Zeilenzahlen
├── cache/releases/           ← Vorgänger-Releases je Version (gitignored)
├── plugins/
│   ├── fishbase/
│   │   ├── import.sh          ← FishBase-Import
│   │   └── sql/
│   │       └── export.sql     ← DuckDB: Parquet → CSV (eine Session)
│   ├── sealifebase/           ← SeaLifeBase-Import, gleicher Aufbau
│   ├── inaturalist/           ← iNaturalist-Taxon-IDs (optional, Netzwerk)
│   └── curated/
│       ├── import.sh          ← Kuratierte Ergänzungen (nur sqlite3)
│       └── data/
│           └── class_common_names.csv
└── tests/
    └── run.sh                 ← ETL-Tests
```

### Verantwortlichkeiten

**`build.sh`** — kennt nur die Reihenfolge der Stages. Übergibt den DB-Pfad an jedes Plugin.

**`core/plugin_order.sh`** — validiert die ausgewählten Plugins und ordnet sie nach `depends_on_sources` (siehe [`docs/plugin-system.md`](docs/plugin-system.md#abhängigkeiten-reihenfolge-und-rang)).

**`core/create_db.sh`** — erstellt die leere DB, legt Schema an. Gibt den DB-Pfad auf stdout aus.

**`plugins/*/import.sh`** — kennt nur seine eigene Datenquelle. Kein Schema, nur Daten. Logs auf stderr.
Sie sourcen idealerweise `core/plugin_api.sh`, damit Logging, Manifest-Parsing und
Source-Metadaten nicht pro Plugin neu geschrieben werden müssen.

### Pipeline-Stages

| Stage | Script | Aufgabe |
|-------|--------|---------|
| 00 | `core/plugin_order.sh` | Plugins validieren, Abhängigkeiten auflösen, Reihenfolge bestimmen |
| 00b | `core/previous_release.sh` | Vorgänger-Release bereitstellen; ohne gültigen Vorgänger Abbruch vor Stage 01 (außer `--initial`) |
| 01 | `core/create_db.sh` | Leere DB + Schema |
| 01b | `core/seed_locale_place_mappings.sh` | Locale → iNaturalist-Place (Netzwerk; entfällt mit `--no-enrich`) |
| 02 | `plugins/*/import.sh` | Quellen mit Entitäten (`placement_priority`, heute `fishbase`, `sealifebase`) importieren, mit vorläufigen IDs |
| 02b | `core/identity.sh` | Endgültige IDs aus dem ID-Register, Zusammenführen, Übernahme aus dem Vorgänger, Aliase |
| 02c | `plugins/*/import.sh` | Ergänzende Quellen (heute `curated`, `inaturalist`) auf den endgültigen IDs |
| 03 | `core/sql/rebuild_lookup.sql` | `species_name_lookup` materialisieren |
| 04 | `core/sql/rebuild_fts.sql` | FTS rebuild über alle Daten (nach allen Plugins) |
| — | `core/report_summary.sh` | Build-Bericht zusammenfassen (Einträge je Quelle und Kategorie) |
| 05 | `core/check_references.sh`, `core/sql/validate.sql` | Verweise auf Entitäten und Mindestzahlen prüfen |

Der Build-Bericht liegt neben der Ausgabe-DB in `<db ohne Endung>.build-report/`,
je Quelle eine TSV mit dem, was sie nicht eindeutig zuordnen konnte; die
Identitäts-Stage schreibt unter `identity` (mehrdeutige Abgleiche,
abweichende Einordnung zusammengeführter Arten).

### Vorgänger-Release

Jeder Build braucht das zuletzt veröffentlichte Release: Aus dessen
ID-Register vergibt die Identitäts-Stage stabile IDs (siehe
[`docs/datenquellen.md`](docs/datenquellen.md#identität)). Stage 00b liest das
Manifest in `discere-data`, lädt die `.gz`, prüft die sha256 und legt die
entpackte DB unter `cache/releases/v<version>/` ab; solange das Manifest
dieselbe Prüfsumme nennt, wird der Cache wiederverwendet. Ohne lesbares
Manifest, bei falscher Prüfsumme oder ohne Referenz-DB bricht der Build ab,
bevor er eine bestehende DB löscht.

- `--previous-release <db>` nimmt eine lokale DB als Vorgänger, etwa ein
  eigenes früheres Build-Ergebnis.
- `--initial` baut ohne Vorgänger und vergibt alle IDs neu ab 1 — nur für
  Tests und einen allerersten Build; das Log warnt.
- `--accept-species-loss <quelle>` nimmt hin, dass eine Quelle mehr als ihre
  Schwelle an Arten des Vorgängers verliert (Default 5 %, siehe
  `docs/datenquellen.md`, Einbruch einer Quelle) — nur zum Testen.

Ein Release entsteht nur aus einem vollständigen Build: Ein Teilbuild mit
`--plugin` liefert die Schlüssel der übrigen Quellen nicht, ihre Entitäten
sind darin übernommen und deprecated. `build.sh` vermerkt in `metadata`, ob
der Build vollständig war (alle Plugins, ohne `--no-enrich`, `--initial` und
`--accept-species-loss`, Vorgänger aus dem Manifest statt
`--previous-release`), gegen welchen
Vorgänger er lief und ob die Validierung bestanden ist; `publish_release.sh`
veröffentlicht nur einen solchen Build gegen das gerade veröffentlichte
Release (`core/check_publishable.sh`).

---

## Verwendung

```bash
# Standardfall: alle Plugins, download + cleanup
./build.sh

# Parquets behalten
./build.sh --keep

# Kein Download — lokale Dateien verwenden
./build.sh --no-download --fishbase-dir ~/data/fishbase/parquet

# Nur ein Plugin (seine Abhängigkeiten laufen mit, hier fishbase)
./build.sh --plugin curated

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
| `--plugin <n>` | Plugin explizit angeben (wiederholbar), Abhängigkeiten aus `depends_on_sources` kommen mit. Ohne Flag: alle Plugins in `plugins/` |
| `--output <path>` | Ziel-Datenbank |
| `--force` | Bestehende DB überschreiben |
| `--download` | Download explizit aktivieren (ist Default wenn kein Flag gesetzt) |
| `--no-download` | Download deaktivieren — lokale Dateien verwenden |
| `--keep` | Heruntergeladene Dateien behalten |
| `--version <v26.07>` | An alle Plugins weitergegeben |
| `--fishbase-dir <path>` | Nur an fishbase-Plugin weitergegeben |
| `--no-enrich` | Stage 01b und optionale Plugins (`optional: true`, heute `inaturalist`) samt ihren Abhängigen überspringen |
| `--previous-release <db>` | Lokale Referenz-DB als Vorgänger statt des veröffentlichten Releases |
| `--initial` | Ohne Vorgänger bauen, alle IDs neu — nur für Tests und einen allerersten Build |

Alle Plugin-Flags gehen an jedes Plugin; ein Plugin ignoriert Flags, die es
nicht kennt, mit einer Warnung.

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
| `DISCERE_RELEASE_MANIFEST_URL` | Manifest des Vorgängers (kein Flag; Default: `discere-data`, `main`) |

---

## Schema

```
classes ──< orders ──< families ──< genera ──< species ──< pictures
                                                            metadata (key/value)
```

Alle Tabellen ausser `pictures` und `metadata`:

| Spalte | Typ | Beschreibung |
|--------|-----|-------------|
| `id` | TEXT PK | ID im Format `discere:<typ>:<nr>` (`species`, `genus`, `family`, `order`, `class`), ohne Quelle, aus dem ID-Register |
| `external_id` | TEXT NOT NULL | ID in der Originalquelle (z.B. `speccode`) |
| `external_source` | TEXT NOT NULL | Quelle (z.B. `fishbase`) — kein Default, explizit setzen |

`external_id` + `external_source` bilden einen Unique Constraint — jede Quell-Entität existiert genau einmal.

**ID-Vergabe:** Plugins erzeugen vorläufige IDs über `discere_uuid(source, entity, external_id)` (`discere:<source>_<entity>:<external_id>`) und verknüpfen damit ihre eigenen Tabellen. Die Identitäts-Stage ersetzt sie durch die endgültigen IDs aus `entity_source_keys`, dem ID-Register: je Quellenschlüssel (`source`, `entity_type`, `external_id`) die Entitäts-ID und ob die Quelle ihn in diesem Build geliefert hat (`active`). `entity_aliases` führt jede frühere ID, die keine Entität mehr bezeichnet, mit ihrer gültigen. Beide Tabellen reisen im Release mit.

**`metadata`** — eine Zeile pro importierter Quelle:

```
key          | value
fishbase     | v26.07
sealifebase  | v26.04
```

---

## Kuratierte Ergänzungen

`plugins/curated/` ist die Quelle `curated` für von Hand gepflegte Daten zu
Entitäten anderer Quellen. Sie legt keine Entitäten an, hängt von `fishbase`
ab und braucht nur `sqlite3`. Beim Import ersetzt sie alle Zeilen mit
`source = 'curated'`.

Klassen findet sie über das ID-Register (`entity_source_keys`) und läuft
deshalb nach der Identitäts-Stage.

Heute pflegt sie `data/class_common_names.csv`: Volksnamen für Klassen, die
eine Taxonquelle nur auf Englisch führt und die bei iNaturalist kein
Gegenstück haben, weil iNaturalist anders gliedert (die FishBase-Klassen
Teleostei, Chondrostei, Cladistii, Dipneusti, Coelacanthi). Je Zeile:
`taxon_source` (Quellenschlüssel der Klasse), `external_id` (ihre Nummer dort,
bei FishBase die ClassNum), `class` (wissenschaftlicher Name), `language`,
`name` und `source_url` als Beleg.

Ein Eintrag gehört hinein, wenn der Name in dieser Sprache etabliert und
belegbar ist (z. B. als Wikidata-Label oder Wikipedia-Titel). Gibt es keinen
solchen Namen, bleibt die Sprache leer, statt einen zu erfinden.

Der Import bricht ab und nennt die betroffenen Zeilen, wenn eine Zelle leer
ist, `taxon_source` nicht in `depends_on_sources` steht, keine Klasse mit
genau dieser Taxonquelle, `external_id` und diesem Namen existiert, die
Sprache nicht `en`, `de`, `fr` oder `es` ist, zwei Zeilen dieselbe Klasse in
derselben Sprache nennen oder die Taxonquelle für die Klasse in dieser Sprache
schon selbst einen Namen führt — zwei Namen derselben Sprache hätten keine
Rangfolge.

---

## Tests

```bash
./tests/run.sh
```

Läuft unter Bash 3.2, braucht `sqlite3`, für den iNaturalist-Fall auch
`duckdb`, und kein Netzwerk. Geprüft werden das Lesen von Manifesten, die
Plugin-Reihenfolge mit Fake-Plugins, Abgleich und Build-Bericht,
`plugins/curated/import.sh` und `plugins/inaturalist/import.sh` gegen eine
Mini-DB, die Identitäts-Stage mit Mini-DBs als Build und Vorgänger sowie das
Laden des Vorgängers über `file://`-URLs. Eine Zeile je Fall, Exit-Code
ungleich 0 bei einem Fehlschlag.

---

## Neues Plugin erstellen

Ein Plugin ist ein `import.sh` in `plugins/<n>/`. Protokoll:

- `plugin.yaml` mit `name`, `version`, `source` (gleich `<n>`) anlegen, bei Abhängigkeiten von anderen Quellen mit `depends_on_sources`
- Liefert das Plugin Entitäten, braucht es eine `placement_priority` und läuft vor der Identitäts-Stage; sonst läuft es danach und adressiert Entitäten über `entity_source_keys` oder den Abgleich
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
Detail-Erklärung und [GitHub Issue #54](https://github.com/discere-app/discere/issues/54) für
das Zielbild. Zwei zusätzliche Skripte hängen an einem lokal gebauten
`discere_reference.db`:

```bash
# Maintainer-only: gebaute DB als Release veröffentlichen (braucht `gh auth login`)
./publish_release.sh --version <n>   # Schemaversion: aus der DB (core/schema_version.sh)

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
- `sqlite3` CLI ab 3.47 (`RAISE` mit Ausdruck in der Identitäts-Stage; `build.sh` prüft die Version)
- `curl` (Vorgänger-Release; Plugins nur bei `--download`)
- `jq`, `gunzip` (Vorgänger-Release)

---

## Hinweise

- `pictures`-IDs sind UUIDs ohne stabilen externen Schlüssel — Picture-IDs nicht in User-Daten referenzieren. Stattdessen `external_id` + `external_source` der zugehörigen Species speichern.
- Externe Mappings in andere Systeme (z.B. iNaturalist) gehören in `entity_external_ids`. Für taxonomische Namens-Enrichments dürfen dort auch normalisierte Schlüssel wie `genus:barbus` oder `family:cyprinidae` verwendet werden, wenn die Laufzeit mit name-basierten Keys arbeitet.
- FTS verwendet FTS4 (nicht FTS5 — im sqflite SQLite-Build auf iOS/Android nicht zuverlässig verfügbar). Rebuild läuft automatisch nach allen Plugins in Stage 04.
- `species` verwendet LEFT JOIN mit `comnames` — alle Spezies werden importiert, auch ohne Common Name.
- FishBase und SeaLifeBase haben (Stand v25.04) keine gemeinsame Art, aber 97 gleichnamige Gattungen und eine gleichnamige Familie — durchweg Homonyme aus verschiedenen Klassen. Höhere Taxa werden deshalb quellenübergreifend nicht zusammengeführt; Arten mit neuem Schlüssel gleicht die Identitäts-Stage über ihren Namen gegen die anderer Quellen ab.
