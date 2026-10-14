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
- Zwei Gruppen: Plugins mit `placement_priority` liefern Entitäten und laufen
  in Stage 02, vor der Identitäts-Stage (02b); alle übrigen ergänzen nur und
  laufen in Stage 02c auf den endgültigen IDs. Warum: siehe
  [`datenquellen.md`](datenquellen.md#abhängigkeiten-und-reihenfolge).
- Innerhalb einer Gruppe läuft jedes Plugin nach den Quellen in seinem
  `depends_on_sources`. Unter den jeweils lauffähigen kommt die alphabetisch
  kleinste zuerst, damit jeder Build dieselbe Reihenfolge hat.
- `--no-enrich` überspringt Plugins mit `optional: true` und jedes Plugin, das
  von einem übersprungenen abhängt.
- Der Build bricht ab bei einem unbekannten Plugin, einer Abhängigkeit ohne
  Plugin, einem Zyklus (die beteiligten Quellen stehen in der Meldung), bei
  zwei ausgewählten Quellen mit derselben `placement_priority` und bei einem
  Plugin mit `placement_priority`, das von einem ohne abhängt.

`placement_priority` entscheidet in der Identitäts-Stage, wessen Zeile und
Einordnung gilt, wenn zwei Quellen dieselbe Art liefern. Jede Quelle, die
Entitäten liefert, braucht einen Wert; eine Quelle ohne Wert liefert keine.
Hintergrund in [`datenquellen.md`](datenquellen.md).

`requires` nennt nur die Werkzeuge, die ein Plugin braucht (`duckdb`,
`sqlite3`, `curl`), nicht andere Quellen.

---

## Abgleich und Build-Bericht

Ein Plugin, das Beiträge an vorhandene Entitäten hängt, ordnet seine
Datensätze nicht selbst zu, sondern über `match_records` aus
[`core/match.sh`](../core/match.sh): eine TSV mit Schlüssel, Rang und
wissenschaftlichem Namen hinein, je Datensatz `matched` mit `entity_id`,
`none` oder `ambiguous` heraus. Die Regeln stehen in
[`datenquellen.md`](datenquellen.md#abgleich).

Was eine externe Quelle nicht zuordnen kann, schreibt sie mit
`plugin_report` in den Build-Bericht, statt abzubrechen; `match_records` tut
das für `none` und `ambiguous` selbst. `build.sh` legt den Bericht je Build
unter `<db ohne Endung>.build-report/` an und fasst ihn vor Stage 05 im Log
zusammen. Eigene, von Hand gepflegte Daten (`curated`) brechen dagegen ab.

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

## IDs

**Plugins dürfen keine IDs selbst konstruieren.**

Plugins erzeugen **vorläufige IDs** ausschliesslich über `discere_uuid()` in
`sql/export.sql`:

```sql
discere_uuid('fishbase', 'species', 12345)
-- → discere:fishbase_species:12345
```

Format: `discere:<source>_<entity>:<external_id>`

Damit verknüpft ein Plugin seine eigenen Tabellen. Eltern-Tabellen werden
zuerst in temporäre DuckDB-Tabellen geladen; Kinder joinen auf diese, um die
IDs als FKs zu übernehmen:

```sql
CREATE TEMP TABLE t_families AS
SELECT discere_uuid('fishbase', 'family', f.famcode) AS id, ...
FROM ... f
LEFT JOIN t_orders o ON o.external_id = CAST(f.ordnum AS VARCHAR);
```

Nach den Plugins mit Entitäten ersetzt die **Identitäts-Stage**
(`core/identity.sh`, Stage 02b) jede vorläufige ID in der ganzen DB durch die
endgültige
`discere:<typ>:<nr>` aus dem ID-Register (`entity_source_keys`), das sie aus
dem vorigen Release übernimmt. Schlüssel einer Entität ist
(`external_source`, Typ, `external_id`); ein Plugin muss deshalb für jede
Entität, die es liefert, eine über Releases stabile `external_id` setzen.
Ergänzende Plugins (`curated`, `inaturalist`) laufen danach und schreiben
direkt endgültige IDs. Sie adressieren Entitäten über das ID-Register
(`entity_source_keys`) oder den Abgleich, nie über ein ID-Format und nicht
über `external_source`/`external_id` der Entitätszeile, die nach einem
Zusammenführen nur noch die Spalten der gewichtigeren Quelle trägt.

Verweist eine neue Spalte auf eine Entität, braucht sie einen Fremdschlüssel
— dann schreibt die Stage sie von selbst um und `core/check_references.sh`
prüft sie am Ende des Builds — oder einen Eintrag in
`REFERENCE_COLUMNS_WITHOUT_FK` in `core/reference_columns.sh`.

Bild-IDs (`pictures.id`) behalten ihr Format: Bilder sind Beiträge, keine
Entitäten, und werden nie von Nutzer-Daten referenziert.

Regeln für Register, Aliase und Lebenszyklus: [`datenquellen.md`](datenquellen.md#identität).

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
- `optional: true` und `placement_priority` stehen nicht zusammen: Eine Quelle mit Entitäten ist nie optional
- `import.sh` existiert und ist ausführbar
- `sql/` Verzeichnis existiert
- `sql/source.sql` existiert

Bei Fehler bricht der Build ab.

Details zur Plugin-API stehen in [`plugin-interface.md`](plugin-interface.md).

---

## Datenbank-Constraints

Das Schema lässt für Entitäten beide ID-Formen zu:

```sql
id TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*:*')
```

Die Identitäts-Stage prüft danach, dass keine vorläufige ID übrig ist und
alle Fremdschlüssel auflösen; `validate.sql` lässt in Stage 05 nur noch
`discere:<typ>:<nr>` zu.

---

## Soft Delete

Entitäten werden nie entfernt, weil User-Daten in `discere_user.db` darauf
referenzieren können. Jeder Build legt die DB neu an; die Identitäts-Stage
übernimmt Entitäten, die keine Quelle mehr liefert, aus dem vorigen Release —
Arten mit `status = 'deprecated'`, samt Namen und Elternkette. Plugins selbst
löschen nur ihre eigenen Beiträge.

---

## FTS Rebuild

FTS-Tabellen werden nicht pro Plugin sondern einmalig nach allen Plugins rebuilt (Stage 04 in `build.sh`). Plugins müssen keinen FTS-Rebuild auslösen.
