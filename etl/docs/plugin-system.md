# Plugin System

Beschreibt das Plugin-Interface des Discere ETL.

---

## Übersicht

Ein Plugin ist ein eigenständiges Script das Daten aus einer externen Quelle in die Discere-Datenbank importiert. `build.sh` orchestriert alle Plugins — Plugins kennen nur ihre eigene Datenquelle.

Wie Quellen künftig vorhandene Daten ergänzen und gemeinsam dieselben Arten liefern, beschreibt das Konzept in [`datenquellen.md`](datenquellen.md).

---

## Plugin-Struktur

Jedes Plugin liegt in `plugins/<name>/`. Der Verzeichnisname ist zugleich
der Quellenschlüssel (`source` im Manifest):

```
plugins/<name>/
    plugin.yaml      ← Plugin-Manifest (Pflicht)
    import.sh        ← Import-Script (Pflicht, muss ausführbar sein)
    sql/
        source.sql   ← sources/metadata-Metadaten (Pflicht)
        export.sql   ← DuckDB-Export-Query (nur parquet-basierte Quellen)
```

Weitere Dateien legt ein Plugin nach Bedarf an, etwa `data/` mit von Hand
gepflegten CSVs (`plugins/curated/`).

Verzeichnisse mit führendem `_` (z.B. `_template`) werden von der Auto-Discovery übersprungen.

---

## Abhängigkeiten, Reihenfolge und Rang

Drei Manifest-Felder steuern, wann ein Plugin läuft und welches Gewicht es hat:

```yaml
depends_on_sources:      # Quellen, gegen deren Daten dieses Plugin abgleicht
  - fishbase
optional: true           # nur ergänzend; --no-enrich überspringt es (Default: false)
placement_priority: 10   # Rang der Einordnung, kleiner = gewichtiger
```

`core/plugin_order.sh` bestimmt daraus vor Stage 01, welche Plugins in welcher
Reihenfolge laufen:

- Ohne `--plugin` gelten alle Plugins, mit `--plugin` die genannten samt ihren
  Abhängigkeiten, transitiv; jede hinzugenommene Abhängigkeit steht im Log.
- Jedes Plugin läuft nach den Quellen in seinem `depends_on_sources`. Unter den
  jeweils lauffähigen kommt die alphabetisch kleinste zuerst, damit jeder Build
  dieselbe Reihenfolge hat.
- `--no-enrich` überspringt Plugins mit `optional: true` und jedes Plugin, das
  von einem übersprungenen abhängt.
- Der Build bricht ab bei einem unbekannten Plugin, einer Abhängigkeit ohne
  Plugin, einem Zyklus (die beteiligten Quellen stehen in der Meldung) und bei
  zwei ausgewählten Quellen mit derselben `placement_priority`.

`placement_priority` wird heute nur geprüft. Entscheiden soll sie, wessen
Einordnung gilt, sobald mehr als eine Quelle Einordnungen liefert; eine Quelle
ohne Wert liefert keine. Hintergrund in [`datenquellen.md`](datenquellen.md).

`requires` nennt nur die Werkzeuge, die ein Plugin braucht (`duckdb`,
`sqlite3`, `curl`), nicht andere Quellen.

---

## Plugin-Kontrakt

Plugins sourcen [`core/plugin_api.sh`](../core/plugin_api.sh) und initialisieren
sich mit:

```bash
source "$PLUGIN_DIR/../../core/plugin_api.sh"
plugin_init "$PLUGIN_DIR"
```

Danach kommen `PLUGIN_SOURCE`, `PLUGIN_SQL_DIR` und die gemeinsamen Helper aus
der Core-API. Externe Entwickler sollen diese API verwenden statt Logging,
Manifest-Parsing oder `metadata`-Writes neu zu implementieren.

### Pflicht-Parameter

```bash
--db <path>    # Pfad zur SQLite-Datenbank — wird von build.sh übergeben
```

### Logs

- Alle Ausgaben auf **stderr**
- Nichts auf stdout (build.sh liest stdout von `create_db.sh`)

### Schema

- **Kein `CREATE TABLE`** — das Schema gehört ausschliesslich in `core/sql/schema.sql`
- Plugins lesen das Schema, schreiben aber keine DDL

### Idempotenz

Vor jedem Import werden eigene Daten gelöscht:

```sql
DELETE FROM pictures WHERE origin = '<source>';
DELETE FROM families WHERE external_source = '<source>';
-- usw.
```

Species und Genera verwenden Soft Delete / INSERT OR IGNORE — nicht löschen.

### Metadata

Nach erfolgreichem Import in `metadata` schreiben:

```sql
INSERT INTO metadata (key, value) VALUES ('<source>', '<version>')
ON CONFLICT (key) DO UPDATE SET value = excluded.value;
```

Das soll über `plugin_write_source_metadata(...)` geschehen, nicht mit
handgeschriebenem Boilerplate pro Plugin.

---

## UUID-Generierung

**Plugins dürfen keine IDs selbst konstruieren.**

IDs werden ausschliesslich über `discere_uuid()` in `sql/export.sql` erzeugt:

```sql
discere_uuid('fishbase', 'species', 12345)
-- → discere:fishbase_species:12345 (als md5-UUID gehashed)
```

Format: `discere:<source>_<entity>:<external_id>`

Warum zentral:
- Format ist immer konsistent
- IDs sind über ETL-Builds hinweg stabil (deterministisch)
- Fehler in Plugins können die User-DB nicht korrumpieren

Eltern-Tabellen werden zuerst in temporäre DuckDB-Tabellen geladen. Kinder joinen auf diese um die UUIDs als FKs zu übernehmen:

```sql
CREATE TEMP TABLE t_families AS
SELECT discere_uuid('fishbase', 'family', f.famcode) AS id, ...
FROM ... f
LEFT JOIN t_orders o ON o.external_id = CAST(f.ordnum AS VARCHAR);
```

---

## Plugin-Validierung

`core/plugin_order.sh` ruft `core/validate_plugin.sh` für jedes ausgewählte
Plugin auf, bevor es dessen Manifest liest. Geprüft wird:

- `plugin.yaml` existiert
- `plugin.yaml` enthält `name`, `version` und `source`
- `plugin.yaml:source` entspricht dem Muster `[a-z0-9][a-z0-9_-]*` und dem Verzeichnisnamen
- `depends_on_sources` ist eine Blockliste von Quellenschlüsseln (gleiches Muster)
- `optional` fehlt oder ist `true`/`false`
- `placement_priority` fehlt oder ist eine ganze Zahl
- `import.sh` existiert und ist ausführbar
- `sql/` Verzeichnis existiert
- `sql/source.sql` existiert

Bei Fehler bricht der Build ab.

Details zur Plugin-API stehen in [`plugin-interface.md`](plugin-interface.md).

---

## Datenbank-Constraints

Das Schema erzwingt das UUID-Format per CHECK-Constraint:

```sql
id TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*_*:*')
```

Ungültige IDs werden von SQLite abgelehnt. `validate.sql` prüft zusätzlich nach dem Import ob alle IDs korrekt sind.

---

## Soft Delete (Species + Genera)

Species und Genera werden nie physisch gelöscht weil User-Daten in `discere_user.db` darauf referenzieren können:

- **Species**: `status = 'deprecated'`, `deprecated_at` wird gesetzt
- **Genera**: `INSERT OR IGNORE` + `UPDATE` — bestehende IDs bleiben erhalten

Andere Tabellen (classes, orders, families, pictures) werden vor jedem Import gelöscht und neu importiert.

---

## FTS Rebuild

FTS-Tabellen werden nicht pro Plugin sondern einmalig nach allen Plugins rebuilt (Stage 04 in `build.sh`). Plugins müssen keinen FTS-Rebuild auslösen.
