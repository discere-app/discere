# Plugin System

Beschreibt das Plugin-Interface des Discere ETL.

---

## Übersicht

Ein Plugin ist ein eigenständiges Script das Daten aus einer externen Quelle in die Discere-Datenbank importiert. `build.sh` orchestriert alle Plugins — Plugins kennen nur ihre eigene Datenquelle.

---

## Plugin-Struktur

Jedes Plugin liegt in `plugins/<name>/` und muss folgende Dateien enthalten:

```
plugins/<name>/
    plugin.yaml      ← Plugin-Metadaten (Pflicht)
    import.sh        ← Import-Script (Pflicht, muss ausführbar sein)
    sql/
        export.sql   ← DuckDB-Export-Query (Pflicht)
```

Verzeichnisse mit führendem `_` (z.B. `_template`) werden von der Auto-Discovery übersprungen.

---

## Plugin-Kontrakt

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

`build.sh` ruft `core/validate_plugin.sh` vor jedem Plugin auf. Geprüft wird:

- `plugin.yaml` existiert
- `import.sh` existiert und ist ausführbar
- `sql/` Verzeichnis existiert
- `sql/export.sql` existiert

Bei Fehler bricht der Build ab.

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

FTS-Tabellen werden nicht pro Plugin sondern einmalig nach allen Plugins rebuilt (Stage 03 in `build.sh`). Plugins müssen keinen FTS-Rebuild auslösen.
