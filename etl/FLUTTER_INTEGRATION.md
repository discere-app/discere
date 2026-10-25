# Flutter Integration — Discere Reference DB

Erklärt wie `discere_reference.db` in eine bestehende Flutter-App integriert wird.

---

## Ausgangslage

Der ETL produziert eine read-only Referenz-DB (`discere_reference.db`) mit Fischarten, Taxonomie und Bildern. Die App hat eine separate User-DB (`discere_user.db`) für Decks und Lernfortschritt. Beide Datenbanken leben getrennt.

---

## Voraussetzungen

```yaml
# pubspec.yaml
dependencies:
  sqflite: ^2.3.0
  path_provider: ^2.1.0
  path: ^1.9.0
  http: ^1.2.0
  crypto: ^3.0.0
```

Die Referenz-DB ist **kein** Flutter Asset mehr (bei ~400MB sprengt sie den
App-Bundle) — sie wird zur Laufzeit heruntergeladen, siehe nächster Abschnitt.

---

## Konzept: Two-Database-Architektur mit Laufzeit-Download

```
discere_reference.db   ← read-only, aus ETL, zur Laufzeit heruntergeladen
discere_user.db        ← read-write, auf Gerät erstellt, User-Daten
```

Die Referenz-DB wird **nicht** gebundelt, sondern beim ersten App-Start von
einer extern gehosteten, versionierten Quelle heruntergeladen (aktuell:
GitHub-Release im `discere-data`-Repo, siehe
[GitHub Issue #54](https://github.com/discere-app/discere/issues/54)
für das Hosting-Konzept). Bei App-Updates wird sie im Hintergrund ersetzt,
falls eine neuere Version verfügbar ist — User-Daten bleiben unberührt, weil
sie in einer separaten Datei liegen.

Die reale Implementierung (nicht nur eine Skizze wie früher in diesem
Dokument) lebt in zwei Klassen im Flutter-Repo:

- **`lib/shared/persistence/reference_database_provisioner.dart`** —
  `ReferenceDatabaseProvisioner`: prüft, ob lokal schon eine nutzbare Kopie
  existiert (`hasUsableLocalCopy()`), sucht nach einer neueren Version
  (`findNewerVersion()`) und legt sie bereit (`stage()`), oder lädt beim
  allerersten Start blockierend mit Fortschrittsanzeige herunter
  (`checkForUpdate()` + `downloadAndInstall(onProgress: ...)`). Was eine
  Sitzung über ein Update weiß und tut, hält
  `ReferenceDbUpdateService` (fail-open — ein fehlgeschlagener Check darf
  eine bereits nutzbare lokale Kopie nie blockieren). Lädt ein kleines `manifest.json`
  (je angebotenem Release Version, Schema-Version, Download-URL,
  SHA-256-Checksum; Format siehe
  [Update-Mechanismus & Publishing](#update-mechanismus--publishing)), wählt
  das neueste lesbare Release, streamt den
  gzip-komprimierten Download direkt in eine `.gz.part`-Datei, verifiziert
  die Checksumme, dekomprimiert in einem Isolate und installiert die Datei
  atomar.
- **`lib/shared/persistence/database_helper.dart`** — `DatabaseHelper` öffnet
  danach nur noch, was der Provisioner bereits an den erwarteten Pfad gelegt
  hat. Kein Asset-Copy-Code mehr hier.
- **`lib/app/bootstrap_app.dart`** — orchestriert den Ablauf: existiert schon
  eine lokale Kopie, startet die App sofort (Hintergrund-Update-Check läuft
  nebenher); existiert keine, zeigt ein eigener Lade-Screen den
  Download-Fortschritt, ausserhalb des normalen 12s-Bootstrap-Timeouts (ein
  mehrere-hundert-MB-Download passt da nicht rein).

---

## Repository-Beispiel

```dart
class SpeciesRepository {
  Future<List<Species>> search(String query) async {
    final db = await DatabaseHelper.referenceDb;

    // FTS4 Suche über alle Sprachen
    final results = await db.rawQuery('''
      SELECT s.*
      FROM species s
      JOIN species_fts fts ON s.id = fts.id
      WHERE species_fts MATCH ?
      ORDER BY s.name
      LIMIT 50
    ''', ['$query*']);

    return results.map(Species.fromMap).toList();
  }

  // Suche über Synonyme aktiver Arten (species_synonyms_fts), in der Form,
  // die ARCH-14 verlangt: die FTS-Tabelle nur im IN-Subquery.
  Future<List<Species>> searchBySynonym(String query) async {
    final db = await DatabaseHelper.referenceDb;
    final results = await db.rawQuery('''
      SELECT s.*
      FROM species s
      WHERE s.id IN (SELECT species_id FROM species_synonyms_fts
                     WHERE species_synonyms_fts MATCH ?)
      ORDER BY s.name
      LIMIT 50
    ''', ['$query*']);

    return results.map(Species.fromMap).toList();
  }

  Future<Species?> findById(String id) async {
    final db = await DatabaseHelper.referenceDb;
    final results = await db.query(
      'species',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? Species.fromMap(results.first) : null;
  }

  Future<List<Picture>> picturesForSpecies(String speciesId) async {
    final db = await DatabaseHelper.referenceDb;
    return (await db.query(
      'pictures',
      where: 'species = ? AND is_usable = 1',
      whereArgs: [speciesId],
    )).map(Picture.fromMap).toList();
  }
}
```

---

## Update-Mechanismus & Publishing

Ablauf, um eine neue `discere_reference.db` an Nutzer:innen auszuliefern
(neuer ETL-Run, neue FishBase-Version):

```
Maintainer:
  ./build.sh                              # neue discere_reference.db bauen
  ./publish_release.sh --version <n+1>   # braucht `gh auth login`; Schemaversion aus der DB
    → gzip + SHA-256
    → Upload als GitHub-Release-Asset auf discere-data
    → Release in data/reference-db/manifest.json in discere-data eintragen
      (schemas["<n>"], bei Schema 1 auch die oberste Ebene) + pushen

App (bei jedem Start, falls schon eine lokale Kopie existiert):
  ReferenceDbUpdateService.checkAtStart()
    → manifest.json laden, neuestes Release mit unterstütztem Schema wählen
      (keins? → Fehler mit Hinweis auf ein App-Update)
    → dessen version > lokal gespeicherte Version?
      → ja: als verfügbar melden; der Hauptbildschirm fragt einmal (abgelehnt
        bleibt es in den Einstellungen herunterladbar), lädt nach
        Bestätigung im Hintergrund mit Fortschritt herunter, verifiziert und
        legt die Datei neben die aktive (<ref>.pending); „Anwenden“ startet
        die App neu, sonst setzt der nächste Start sie ein
      → nein: nichts tun
    → Fehler beim Check (offline, Server down)? → lokale Kopie bleibt aktiv
      (fail-open); nur die Einstellungen nennen den Fehlschlag und bieten
      eine neue Suche an

App (bei jedem Start, vor allem anderen):
  installStagedUpdate()  → bereitgelegte Datei einsetzen und stempeln

App (bei jedem Start, sobald eine Referenz-DB bereitliegt):
  applyReferenceIdAliases()  → ReferenceIdMigration
    → Aliase dieser Version schon angewendet? → nichts tun
    → sonst: Verweise der Nutzer-DB und der Watchlist über entity_aliases
      umschreiben, dann erst die Dienste bauen
```

### Manifest

`data/reference-db/manifest.json` nennt unter `schemas` je Schemaversion
deren neuestes Release, mit der Schemaversion als Schlüssel. Die oberste
Ebene ist immer das neueste Release mit Schemaversion 1 — für App-Versionen,
die `schemas` nicht kennen und nur sie lesen:

```json
{
  "version": 2, "schemaVersion": 1, "url": "…", "sha256": "…",
  "compressedSizeBytes": 85839399, "publishedAt": "…",
  "schemas": {
    "1": { "version": 2, "url": "…", "sha256": "…", "compressedSizeBytes": 85839399, "publishedAt": "…" },
    "2": { "version": 3, "url": "…", "sha256": "…", "compressedSizeBytes": 0, "publishedAt": "…" }
  }
}
```

`version` zählt über alle Schemas hinweg; jedes Release bekommt eine höhere
als alle bisherigen. Jede App bekommt das neueste Release, das sie lesen
kann: unter den Einträgen mit einer unterstützten Schemaversion das mit der
höchsten `version`, bei Gleichstand das mit der höheren Schemaversion
(`ReferenceDbManifest.newestReadable` in
`lib/shared/persistence/reference_db_manifest.dart`). Steht `schemas` im
Manifest, gelten nur seine Einträge; fehlt es, gilt die oberste Ebene allein.
Unbekannte Felder ignoriert die App. Ein Schemawechsel braucht deshalb keine
Reihenfolge von App- und Release-Auslieferung.

`publish_release.sh` schreibt das Manifest über `core/manifest_update.sh`
fort: Es setzt den Eintrag der Schemaversion des Releases und nur bei
Schemaversion 1 auch die oberste Ebene. Ein Manifest ohne `schemas` bekommt
seine bisherige oberste Ebene als `schemas["1"]`; hat diese eine andere
Schemaversion als 1, bricht das Skript ab. Vorgänger des nächsten Builds und
Maßstab der Prüfung vor dem Veröffentlichen ist das neueste Release über
alle Schemaversionen (`core/manifest_newest.sh`), nach derselben Regel wie
in der App: Neben `schemas` zählt die oberste Ebene nicht, denn ein Release,
das nur dort stünde, installierte keine App, die `schemas` liest.

`schemaVersion` ist von `version` (reine Datenupdates) getrennt —
nur hochzählen, wenn sich `core/sql/schema.sql` so ändert, dass die
Flutter-seitigen Queries in `lib/catalog/repository/` oder das Umschreiben
der Nutzerdaten eine passende App-Version brauchen. Schemaversion 2 ist die
erste mit `entity_aliases`. Die App akzeptiert die Schemaversionen 1 und 2
(`ReferenceDatabaseProvisioner.supportedSchemaVersions`): Eine installierte
Schema-1-Kopie bleibt nutzbar, das erste Schema-2-Release kommt über das
normale Bereitstellen und den Neustart; bei Schema 1 hat die
Alias-Migration nichts umzuschreiben.

User-Decks und Lernfortschritt liegen in `discere_user.db` und überstehen
jedes Update. Verweisen sie auf eine ID, die das neue Release abgelöst hat,
schreibt die App sie beim nächsten Start auf die gültige um.

---

## Häufige Fehler

**FTS-Query ohne Wildcard gibt keine Ergebnisse**
FTS4 matcht auf vollständige Tokens. `MATCH 'salmo'` findet `Salmo trutta`, `MATCH 'salm'` nicht. Immer `MATCH '$query*'` verwenden für Prefix-Suche.

**`read-only` wirft Exception bei Write-Versuch**
Korrekt so — alle Schreiboperationen gehören in die User-DB. Wenn ein Repository versehentlich in die Referenz-DB schreibt, ist das ein Architektur-Fehler.

**`species_id` in User-DB referenziert**
`flashcard_stats.species_id` zeigt auf `species.id` aus der Referenz-DB. Diese IDs (`discere:species:<nr>`) vergibt das ETL über ein ID-Register stabil über Releases und dürfen als interne Schlüssel in der App verwendet werden. Wird eine ID abgelöst, führt `entity_aliases` sie mit ihrer gültigen; die App schreibt ihre Verweise beim Wechsel der Referenz-DB darüber um (siehe `docs/datenquellen.md`, Aliase). `external_source` + `external_id` bleiben Herkunftsinfo der Entity selbst.

---

## Neu: Bildanzeige mit Lizenz-Compliance

Die `pictures`-Tabelle hat zwei neue Felder: `license_key` (normierter Lizenz-String)
und `is_usable` (0/1, beim ETL-Import berechnet). **Bilder mit `is_usable = 0` dürfen
in der App niemals angezeigt werden** — das ist eine rechtliche Anforderung, keine
optionale Optimierung.

### Was zu tun ist

**1. `Picture`-Model erweitern**

```dart
class Picture {
  final String id;
  final String species;
  final String? picname;
  final String? picturetype;
  final String? lifestage;
  final String? author;       // Fotograf / Organisation — für Attribution
  final String? copyright;    // Rohtext aus der Quelle
  final String? url;
  final String origin;
  final String? licenseKey;   // normiert, z.B. 'CC BY-NC 4.0'
  final int isUsable;         // 1 = darf angezeigt werden

  const Picture({ ... });

  factory Picture.fromMap(Map<String, dynamic> map) => Picture(
    id:         map['id'] as String,
    species:    map['species'] as String,
    picname:    map['picname'] as String?,
    picturetype: map['picturetype'] as String?,
    lifestage:  map['lifestage'] as String?,
    author:     map['author'] as String?,
    copyright:  map['copyright'] as String?,
    url:        map['url'] as String?,
    origin:     map['origin'] as String,
    licenseKey: map['license_key'] as String?,
    isUsable:   (map['is_usable'] as int?) ?? 0,
  );

  /// Attributionstext für die UI.
  /// Laut FishBase-Lizenz muss bei jedem Bild stehen:
  ///   "© [Fotograf], from FishBase ([Lizenz])"
  String get attributionText {
    final who   = (author?.isNotEmpty == true) ? author! : origin;
    final lic   = licenseKey ?? 'ARR';
    return '© $who, from ${_sourceName(origin)} ($lic)';
  }

  String _sourceName(String origin) => switch (origin) {
    'fishbase'    => 'FishBase',
    'sealifebase' => 'SeaLifeBase',
    _             => origin,
  };
}
```

**2. `SpeciesRepository.picturesForSpecies()` anpassen**

Nur nutzbare Bilder zurückgeben — Filter auf DB-Ebene, nicht im Widget.

```dart
Future<List<Picture>> picturesForSpecies(String speciesId) async {
  final db = await DatabaseHelper.referenceDb;
  return (await db.query(
    'pictures',
    where: 'species = ? AND is_usable = 1',  // ← neu
    whereArgs: [speciesId],
  )).map(Picture.fromMap).toList();
}
```

**3. Attribution im Widget anzeigen**

Bei jedem angezeigten Bild muss `picture.attributionText` sichtbar sein —
als Overlay, Caption oder Tooltip. Kein Bild ohne Attribution.

```dart
class PictureCard extends StatelessWidget {
  final Picture picture;
  const PictureCard({super.key, required this.picture});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Image.network(
          picture.url!,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.image_not_supported),
        ),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              picture.attributionText,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }
}
```

### Häufige Fehler

**`is_usable`-Filter vergessen**
Wenn `picturesForSpecies()` ohne `AND is_usable = 1` abfragt, werden auch
gesperrte Bilder zurückgegeben. Der Filter gehört zwingend in die DB-Query,
nicht ins Widget — sonst ist ein vergessener UI-Check ein Lizenzverstoß.

**Attribution weglassen oder verstecken**
Die Attribution muss für den Nutzer lesbar sein. Ein unsichtbarer Text
oder ein ausgeblendetes Element erfüllt die Lizenzanforderung nicht.

**`author` ist NULL**
Bei Field-Guide-Bildern und einigen Einträgen ohne Fotografenangabe ist
`author` NULL. In diesem Fall `origin` als Fallback verwenden
(bereits in `attributionText` implementiert).

---

## Neu: iNaturalist Bildabruf via taxon_id

### Hintergrund

Bisher wurde bei fehlendem Bild die iNaturalist-API mit dem wissenschaftlichen
Namen durchsucht (`/v1/taxa?q=<name>`). Das führte häufig zu Fehlern:
- Nur das erste Resultat wurde geprüft
- iNaturalist liefert Genus, Subspecies und Synonyme in den Resultaten
- Arten die iNat intern umbenannt hat (`active = false`) wurden gar nicht gefunden

### Neue Architektur

Der ETL-Build schreibt iNaturalist-Taxon-IDs als generisches
External-ID-Mapping direkt in die DB (Tabelle `entity_external_ids`).
Species werden über den vollen Binomialnamen gematcht (`Genus + species`),
höhere Taxonomie-Ränge zusätzlich über normalisierte Name-Keys wie
`genus:barbus` oder `family:cyprinidae`. FishBase/SeaLifeBase ist der
taxonomische Master.

```
ETL-Build:
  taxa.csv (iNaturalist AWS Open Data)
    → JOIN auf genus + species (Binomialname)
    → JOIN auf genus/family/order/class Namen
    → nur Taxa, die zur eigenen Kette jeder gleichnamigen Entität passen
      (docs/datenquellen.md, Stamm und Kette bei der iNaturalist-Zuordnung)
    → entity_external_ids befüllen
    → bewusst nicht zugeordnete Entitäten → entity_external_id_rejections
    → je Klasse die iNat-IDs passender Stämme und Klassen
      → inat_allowed_ancestors

App:
  external_id(provider='inaturalist') in Referenz-DB?
    → direkt per taxon_id auf Foto-/Namens-Endpunkte
  fehlt?
    → Fallback: User-DB-Cache prüfen
    → in entity_external_id_rejections? → keine Suche, keine iNat-Daten
    → sonst /v2/taxa?q=name&rank=…&fields=…,ancestor_ids, Treffer nur mit
      erlaubtem Stamm (höhere Ränge: und Klasse) aus inat_allowed_ancestors,
      nie das erste Ergebnis (docs/enrichment.md, Die iNat-Taxon-ID)
```

### Schema

```sql
-- Bereits in der DB vorhanden
SELECT * FROM entity_external_ids WHERE provider = 'inaturalist' LIMIT 5;
-- entity_id                       | entity_type | provider    | external_id
-- discere:species:10042         | species     | inaturalist | 12345
-- genus:barbus                   | genera      | inaturalist | 86989
-- family:cyprinidae              | families    | inaturalist | 51783

-- Ab refdb-v3; ältere Referenz-DBs haben die beiden Tabellen nicht, die
-- App prüft das einmal je geöffneter DB (OptionalReferenceTable).
SELECT * FROM entity_external_id_rejections WHERE provider = 'inaturalist' LIMIT 2;
-- entity_id                     | entity_type | provider    | reason
-- discere:species:120678        | species     | inaturalist | phylum_mismatch
-- genus:megalomma               | genera      | inaturalist | phylum_mismatch

SELECT * FROM inat_allowed_ancestors WHERE class_id = 'discere:class:77';  -- Gastropoda
-- class_id         | rank   | inat_taxon_id
-- discere:class:77 | class  | 47114
-- discere:class:77 | phylum | 47115
```

### Repository

```dart
class ExternalIdRepository {
  Future<String?> getExternalId(String entityId, String provider) async {
    final db = await DatabaseHelper.referenceDb;
    final result = await db.query(
      'entity_external_ids',
      columns: ['external_id'],
      where: 'entity_id = ? AND provider = ?',
      whereArgs: [entityId, provider],
      limit: 1,
    );
    return result.isNotEmpty ? result.first['external_id'] as String : null;
  }
}
```

### Häufige Fehler

**iNaturalist-Mapping fehlt für viele Arten**
Prüfen ob der ETL-Build das Plugin `inaturalist` ausgeführt hat (`--no-enrich` überspringt es):
```bash
sqlite3 assets/database/discere_reference.db \
  "SELECT COUNT(*) FROM entity_external_ids WHERE provider = 'inaturalist';"
```
Sollte > 0 sein. Falls 0: `./etl/plugins/inaturalist/import.sh --db <db>` laufen lassen. Was sich nicht eindeutig zuordnen ließ, steht im Build-Bericht (`<db ohne Endung>.build-report/inaturalist.tsv`).

**Fallback liefert immer noch keine Treffer**
Der ETL arbeitet mit aktiven Taxa aus `taxa.csv`. Für echte Lücken greift die
App auf den User-DB-Cache zurück und resolved erst danach live via
`/v2/taxa?q=name`. Eine Entität in `entity_external_id_rejections` sucht sie
nie, eine Art ohne Kette bis zur Klasse oder mit Platzhalter-Stamm ebenso
nicht, und ein Treffer ohne erlaubten Stamm zählt nicht — gewollt, lieber
keine Zuordnung als eine falsche.
