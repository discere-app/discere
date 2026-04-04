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
```

Die Referenz-DB kommt als Flutter Asset:

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/database/discere_reference.db
```

---

## Konzept: Two-Database-Architektur

```
discere_reference.db   ← read-only, aus ETL, als Asset gebundelt
discere_user.db        ← read-write, auf Gerät erstellt, User-Daten
```

Die Referenz-DB wird beim ersten App-Start aus den Assets in das beschreibbare App-Verzeichnis kopiert und dort **read-only** geöffnet. Bei App-Updates wird sie ersetzt falls sich die Version geändert hat — User-Daten bleiben unberührt weil sie in einer separaten Datei liegen.

---

## DatabaseHelper

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static Database? _referenceDb;
  static Database? _userDb;

  // ---------------------------------------------------------------------------
  // Referenz-DB (read-only)
  // ---------------------------------------------------------------------------

  static Future<Database> get referenceDb async {
    _referenceDb ??= await _openReferenceDb();
    return _referenceDb!;
  }

  static Future<Database> _openReferenceDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = join(dir.path, 'discere_reference.db');

    await _copyAssetIfNeeded(dbPath);

    return openDatabase(
      dbPath,
      readOnly: true,
      // Kein onCreate/onUpgrade — Schema kommt aus dem ETL
    );
  }

  /// Kopiert die DB aus den Assets wenn sie noch nicht existiert
  /// oder die ETL-Version neuer ist als die lokale Kopie.
  static Future<void> _copyAssetIfNeeded(String dbPath) async {
    final dbFile = File(dbPath);

    if (await dbFile.exists()) {
      final shouldUpdate = await _isNewerVersionAvailable(dbPath);
      if (!shouldUpdate) return;
    }

    final data = await rootBundle.load('assets/database/discere_reference.db');
    final bytes = data.buffer.asUint8List();
    await dbFile.writeAsBytes(bytes, flush: true);
  }

  /// Vergleicht die Version in der Asset-DB mit der lokalen Kopie.
  /// Verwendet die metadata-Tabelle: SELECT value FROM metadata WHERE key = 'fishbase'
  static Future<bool> _isNewerVersionAvailable(String localDbPath) async {
    try {
      // Lokale Version lesen
      final localDb = await openDatabase(localDbPath, readOnly: true);
      final localResult = await localDb.rawQuery(
        "SELECT value FROM metadata WHERE key = 'fishbase'",
      );
      await localDb.close();
      final localVersion = localResult.isNotEmpty
          ? localResult.first['value'] as String
          : '';

      // Asset-Version lesen (temporär in Memory öffnen)
      final dir = await getTemporaryDirectory();
      final tempPath = join(dir.path, 'discere_check.db');
      final data = await rootBundle.load('assets/database/discere_reference.db');
      await File(tempPath).writeAsBytes(data.buffer.asUint8List());
      final assetDb = await openDatabase(tempPath, readOnly: true);
      final assetResult = await assetDb.rawQuery(
        "SELECT value FROM metadata WHERE key = 'fishbase'",
      );
      await assetDb.close();
      await File(tempPath).delete();

      final assetVersion = assetResult.isNotEmpty
          ? assetResult.first['value'] as String
          : '';

      return assetVersion != localVersion;
    } catch (_) {
      // Im Fehlerfall immer neu kopieren
      return true;
    }
  }

  // ---------------------------------------------------------------------------
  // User-DB (read-write)
  // ---------------------------------------------------------------------------

  static Future<Database> get userDb async {
    _userDb ??= await _openUserDb();
    return _userDb!;
  }

  static Future<Database> _openUserDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = join(dir.path, 'discere_user.db');

    return openDatabase(
      dbPath,
      version: 1,
      onCreate: _createUserSchema,
      onUpgrade: _upgradeUserSchema,
    );
  }

  static Future<void> _createUserSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE decks (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        created_at  TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE flashcard_stats (
        id          TEXT PRIMARY KEY,
        species_id  TEXT NOT NULL,
        deck_id     TEXT NOT NULL REFERENCES decks(id),
        due_at      TEXT,
        interval    INTEGER DEFAULT 0,
        ease        REAL    DEFAULT 2.5
      )
    ''');
  }

  static Future<void> _upgradeUserSchema(
      Database db, int oldVersion, int newVersion) async {
    // Migrations hier hinzufügen wenn nötig
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  static Future<void> close() async {
    await _referenceDb?.close();
    await _userDb?.close();
    _referenceDb = null;
    _userDb = null;
  }
}
```

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

## Update-Mechanismus

Wenn eine neue `discere_reference.db` ausgeliefert wird (neuer ETL-Run, neue FishBase-Version), passiert beim nächsten App-Start automatisch folgendes:

```
App startet
  → _openReferenceDb()
  → _copyAssetIfNeeded()
  → _isNewerVersionAvailable()
    → lokale metadata: fishbase = v25.04
    → asset metadata:  fishbase = v25.07   ← neu
    → verschieden → return true
  → Asset wird neu kopiert
  → Neue DB ist aktiv
  → User-DB bleibt unberührt
```

User-Decks und Lernfortschritt sind davon nicht betroffen weil sie in `discere_user.db` liegen.

---

## Häufige Fehler

**FTS-Query ohne Wildcard gibt keine Ergebnisse**
FTS4 matcht auf vollständige Tokens. `MATCH 'salmo'` findet `Salmo trutta`, `MATCH 'salm'` nicht. Immer `MATCH '$query*'` verwenden für Prefix-Suche.

**DB ist nach Update leer**
`_copyAssetIfNeeded` öffnet die DB vor dem Schreiben nicht — sicherstellen dass `_referenceDb` vorher geschlossen wird wenn die App im Hintergrund läuft.

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

Der ETL-Build schreibt für jede gematchte Art die iNaturalist-ID als generisches
External-ID-Mapping direkt in die DB (Tabelle `entity_external_ids`). FishBase/SeaLifeBase ist der taxonomische Master —
auch Arten die iNaturalist intern umbenannt hat werden gemapped, da die
`taxon_id` weiterhin gültig für Foto-Abfragen ist.

```
ETL-Build:
  taxa.csv (iNaturalist AWS Open Data)
    → JOIN auf species.name
    → entity_external_ids befüllen

App:
  external_id(provider='inaturalist') in Referenz-DB?
    → direkt /v1/observations?taxon_id=XXXX&photos=true
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
-- discere:fishbase_species:10043 | species     | inaturalist | 67890
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
iNaturalist markiert Arten als `active = false` wenn sie intern umbenannt wurden.
Der ETL matched trotzdem (FishBase ist Master), aber der Fallback-Namenssuche
fehlt der Filter — `/v1/taxa?q=name` liefert aktive Taxa bevorzugt.
Lösung: taxon_id via ETL sicherstellen, Fallback ist nur für echte Lücken gedacht.
