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
[`../misc/tasks/reference-db-target-architecture.md`](../misc/tasks/reference-db-target-architecture.md)
für das Hosting-Konzept). Bei App-Updates wird sie im Hintergrund ersetzt,
falls eine neuere Version verfügbar ist — User-Daten bleiben unberührt, weil
sie in einer separaten Datei liegen.

Die reale Implementierung (nicht nur eine Skizze wie früher in diesem
Dokument) lebt in zwei Klassen im Flutter-Repo:

- **`lib/shared/persistence/reference_database_provisioner.dart`** —
  `ReferenceDatabaseProvisioner`: prüft, ob lokal schon eine Kopie existiert
  (`hasLocalCopy()`), aktualisiert bei Bedarf im Hintergrund
  (`ensureUpToDateInBackground()`, fail-open — ein fehlgeschlagener Check
  darf eine bereits nutzbare lokale Kopie nie blockieren), oder lädt beim
  allerersten Start blockierend mit Fortschrittsanzeige herunter
  (`downloadInitialCopy(onProgress: ...)`). Lädt ein kleines `manifest.json`
  (Version, Schema-Version, Download-URL, SHA-256-Checksum), streamt den
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
  ./publish_release.sh --version <n+1> --schema-version <n>   # braucht `gh auth login`
    → gzip + SHA-256
    → Upload als GitHub-Release-Asset auf discere-data
    → data/reference-db/manifest.json in discere-data aktualisieren + pushen

App (bei jedem Start, falls schon eine lokale Kopie existiert):
  ReferenceDatabaseProvisioner.ensureUpToDateInBackground()
    → manifest.json laden
    → manifest.version > lokal gespeicherte Version?
      → ja: im Hintergrund neu herunterladen, verifizieren, installieren
      → nein: nichts tun
    → Fehler beim Check (offline, Server down)? → lokale Kopie bleibt aktiv,
      kein Fehler für die Nutzer:in sichtbar (fail-open)
```

`schemaVersion` im Manifest ist von `version` (reine Datenupdates) getrennt —
nur hochzählen, wenn sich `core/sql/schema.sql` so ändert, dass die
Flutter-seitigen Queries in `lib/catalog/repository/` eine passende
App-Version brauchen.

User-Decks und Lernfortschritt sind von alldem nicht betroffen, weil sie in
`discere_user.db` liegen.

---

## Häufige Fehler

**FTS-Query ohne Wildcard gibt keine Ergebnisse**
FTS4 matcht auf vollständige Tokens. `MATCH 'salmo'` findet `Salmo trutta`, `MATCH 'salm'` nicht. Immer `MATCH '$query*'` verwenden für Prefix-Suche.

**`read-only` wirft Exception bei Write-Versuch**
Korrekt so — alle Schreiboperationen gehören in die User-DB. Wenn ein Repository versehentlich in die Referenz-DB schreibt, ist das ein Architektur-Fehler.

**`species_id` in User-DB referenziert**
`flashcard_stats.species_id` zeigt auf `species.id` aus der Referenz-DB. Diese IDs sind im aktuellen ETL deterministisch (`discere:<source>_species:<external_id>`) und dürfen als interne Schlüssel in der App verwendet werden. `external_source` + `external_id` bleiben trotzdem wichtig, aber nur als Herkunftsinfo der Entity selbst.

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
    → entity_external_ids befüllen

App:
  external_id(provider='inaturalist') in Referenz-DB?
    → direkt per taxon_id auf Foto-/Namens-Endpunkte
  fehlt?
    → Fallback: User-DB-Cache prüfen
    → danach erst /v1/taxa?q=name&rank=species&per_page=10
```

### Schema

```sql
-- Bereits in der DB vorhanden
SELECT * FROM entity_external_ids WHERE provider = 'inaturalist' LIMIT 5;
-- entity_id                       | entity_type | provider    | external_id
-- discere:fishbase_species:10042 | species     | inaturalist | 12345
-- genus:barbus                   | genera      | inaturalist | 86989
-- family:cyprinidae              | families    | inaturalist | 51783
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
Prüfen ob der ETL-Build den iNaturalist-Enrichment-Schritt ausgeführt hat:
```bash
sqlite3 assets/database/discere_reference.db \
  "SELECT COUNT(*) FROM entity_external_ids WHERE provider = 'inaturalist';"
```
Sollte > 0 sein. Falls 0: ETL nochmals mit `./etl/enrichment/inaturalist/enrich.sh` laufen lassen.

**Fallback liefert immer noch keine Treffer**
Der ETL arbeitet mit aktiven Taxa aus `taxa.csv`. Für echte Lücken greift die
App auf den User-DB-Cache zurück und resolved erst danach live via
`/v1/taxa?q=name`. Der Fallback ist nur für nicht gematchte oder neue Taxa
gedacht, nicht für den Regelfall.
