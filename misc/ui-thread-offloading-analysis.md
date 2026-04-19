# UI Thread Offloading Analysis

## Kurzfassung

Discere hat noch spürbares Potenzial, Arbeit aus dem UI-Isolate herauszunehmen. Die größten Hebel liegen nicht in Widget-Builds selbst, sondern in:

1. App-Start vor `runApp()`
2. JSON/GZIP-Serialisierung und -Parsing
3. Search-Postprocessing und Remote-JSON-Decoding
4. Species-Hydration und Mapping größerer Ergebnismengen
5. Ungebremsten Fan-out-Pfaden bei Flashcards/Watchlist

Wichtig: Nicht alles darf in einen Background-Isolate verschoben werden. Alles, was über Flutter-Plugins oder Platform Channels läuft, bleibt grundsätzlich am Haupt-Isolate angebunden. Das betrifft hier vor allem `sqflite`, `shared_preferences`, `path_provider`, `rootBundle` und `flutter_local_notifications`. Verschiebbar ist vor allem reine Dart-Arbeit: JSON, GZIP, String-Normalisierung, Ranking, Merging, Mapping, Sortierung, Hashing.

## Was sich wirklich in Background-Threads verlagern lässt

Saubere Kandidaten für Isolates:

- `jsonEncode` / `jsonDecode`
- `gzip.encode` / `gzip.decode`
- Base64-Encoding/Decoding
- Ranking, Merge- und Sortierlogik
- Mapping von rohen Maps/DTOs in UI/View-Model-nahe Strukturen
- Normalisierung großer Stringmengen

Nicht direkt in Isolates verschiebbar:

- `sqflite`-Queries selbst
- `SharedPreferences.getInstance()`
- `rootBundle.load(...)`
- `getApplicationDocumentsDirectory()` / `getApplicationSupportDirectory()`
- Notification-Plugin-Aufrufe
- Provider-/Widget-/`setState`-Arbeit

Die saubere Strategie ist deshalb meistens: **I/O und Plugin-Zugriffe dort lassen, wo sie sind, aber das teure Dart-Postprocessing in Worker-Isolates auslagern.**

## 1. Startpfad vor `runApp()` ist zu schwer

**Status-Check (2026-04-19): weiterhin relevant**

Der Punkt trifft noch zu. `main()` wartet weiterhin `setupServices()` komplett vor `runApp()` ab, inklusive `SharedPreferences`, Locale-Mapping, Notification-Init und `backgroundScheduler.initialize()` in `lib/main.dart`. Auch die Referenz-DB wird beim ersten Zugriff weiter über `DatabaseHelper.referenceDb` aus den Assets kopiert und geöffnet.

### Fundstellen

- `lib/main.dart:47-57`
- `lib/main.dart:60-140`
- `lib/shared/persistence/database_helper.dart:49-87`

### Warum das ein Problem ist

Der komplette Bootstrap läuft aktuell vor dem ersten Frame:

- `setupServices()` wird vor `runApp()` vollständig abgewartet
- dabei werden `SharedPreferences`, Locale-Mapping und Notification-Init geladen
- zusätzlich wird beim ersten DB-Zugriff die Referenzdatenbank aus den Assets kopiert

Das ist besonders kritisch, weil die gebündelte DB groß ist:

- `assets/database/discere_reference.db`: ca. `285 MB`

Solange dieser Pfad läuft, kann Flutter die eigentliche App noch nicht rendern. Das ist technisch kein klassischer "Jank", aber es ist derselbe Engpass: zu viel Arbeit am Main-Isolate, bevor überhaupt UI sichtbar wird.

### Saubere Behebung

- `runApp()` sofort starten und nur einen sehr leichten Bootstrap-Shell rendern
- Services in `critical` und `deferred` aufteilen
- nur absolut notwendige Dependencies für den ersten Screen synchron bereitstellen
- Locale-Mapping, Notification-Init und ähnliche Nebenpfade nach dem ersten Frame nachladen
- DB-Kopie nicht mehr implizit im globalen Setup verstecken, sondern als expliziten Bootstrap-Step mit Status/Progress modellieren

Saubere Zielarchitektur:

- `BootstrapApp` startet sofort
- `BootstrapController` lädt initiale Ressourcen
- UI zeigt Splash/Loading-State
- nach erfolgreichem Bootstrap werden echte Provider injiziert

Wichtig:

- `rootBundle` und `path_provider` sollten nicht in einen Worker-Isolate umziehen
- der Gewinn kommt hier primär aus **Entkopplung vom ersten Frame**, nicht aus blindem `compute()`

## 2. Import/Export/Share macht teure JSON- und GZIP-Arbeit am UI-Isolate

**Status-Check (2026-04-19): weiterhin relevant**

Der Punkt trifft ebenfalls noch zu. In `lib/learning/share/share_deck_page.dart` werden `JsonExportUtil.encode(fullDeck)` und `jsonEncode(fullDeck.toJson())` weiterhin direkt im `FutureBuilder`-Pfad erzeugt. Auch `ImportExportService`, `DeckImportService` und `RemoteDeckService` machen JSON-/GZIP-Arbeit weiterhin synchron im Main-Isolate; ein dedizierter Worker/Isolate ist dafür aktuell nicht vorhanden.

### Fundstellen

- `lib/learning/share/share_deck_page.dart:160-181`
- `lib/learning/service/import_export_service.dart:20-28`
- `lib/learning/service/import_export_service.dart:98-105`
- `lib/shared/util/json_export_util.dart:8-25`
- `lib/learning/model/create_deck.dart:34-38`
- `lib/learning/service/deck_import_service.dart:37-66`
- `lib/learning/service/remote_deck_service.dart:18-57`
- `lib/learning/service/remote_deck_service.dart:82-94`
- `lib/learning/import/import_json_tab.dart:36-45`

### Warum das ein Problem ist

Hier laufen mehrere teure CPU-Schritte direkt im Main-Isolate:

- JSON serialisieren
- JSON parsen
- GZIP komprimieren/dekomprimieren
- Base64 kodieren/dekodieren
- große Decks im Share-Screen bereits im `build()` vorbereiten

Besonders ungünstig ist `ShareDeckPage`: dort werden `JsonExportUtil.encode(fullDeck)` und `jsonEncode(fullDeck.toJson())` direkt im `FutureBuilder`-Build erzeugt. Jeder Rebuild kann diese Arbeit erneut anstoßen.

Bei kleinen Decks merkt man das kaum. Bei größeren Decks oder QR-Exports produziert das genau die Art von kurzen Hängern, die sich nach "da steckt noch viel auf dem UI-Thread" anfühlen.

### Saubere Behebung

- Einen dedizierten `DeckSerializationWorker` als Isolate einführen
- nur plain data übergeben: `Map<String, dynamic>` oder `Uint8List`
- folgende Arbeit dort ausführen:
  - JSON stringify/parse
  - GZIP encode/decode
  - Base64 encode/decode
- Ergebnis zurück an den Main-Isolate liefern

Konkret:

- `ShareDeckPage` berechnet Exportdaten einmal in `initState()` oder in einer gecachten `Future`, nicht im `build()`
- `ImportExportService.exportDeckToJson()` und `exportDeckToGzip()` delegieren an den Worker
- `DeckImportService.importJson()` und `importGzip()` parsen im Worker
- `RemoteDeckService` decodiert HTTP-Responses ebenfalls im Worker

Das ist ein sehr sauberer erster Schritt, weil diese Pfade fast nur aus reiner Dart-Arbeit bestehen.

## 3. Suche: DB ist schon relativ gut optimiert, aber das Postprocessing sitzt noch auf dem UI-Isolate

**Status-Check (2026-04-19): teilweise entschärft, aber nicht erledigt**

Der Punkt ist nicht mehr ganz so scharf wie ursprünglich, aber weiterhin relevant. Positiv: `SearchRepository` hat inzwischen einen abgespeckten `searchQuick()`-Pfad für Live-Suche sowie serialisierte Suchpfade zur Entlastung der DB-Queue. Nicht gelöst ist aber das eigentliche Dart-Postprocessing nach den Queries: Candidate-Building, Merge, Ranking, Sortierung und Mapping laufen weiterhin im Main-Isolate. Dazu kommt, dass JSON-Decoding in `INaturalistService` und `WikiService` weiterhin direkt nach den HTTP-Responses im selben Isolate passiert.

### Fundstellen

- `lib/catalog/repository/search_repository.dart:77-141`
- `lib/catalog/repository/search_repository.dart:243-286`
- `lib/catalog/repository/search_repository.dart:288-417`
- `lib/catalog/repository/search_repository.dart:1176-1224`
- `lib/shared/external/inaturalist_service.dart:50-80`
- `lib/shared/external/inaturalist_service.dart:263-281`
- `lib/shared/external/inaturalist_service.dart:311-327`
- `lib/shared/external/wiki_service.dart:21-64`
- `lib/shared/external/wiki_service.dart:67-100`

### Warum das ein Problem ist

Die eigentlichen SQL-Queries sind bereits spürbar optimiert. Das Problem liegt jetzt eher im Rest:

- Search-Term normalisieren
- Kandidaten aufbauen
- Common Names mergen
- Ergebnisse deduplizieren
- sortieren und ranken
- iNaturalist-/Wikimedia-JSON im Main-Isolate parsen

Gerade die Suche ist sensitiv, weil diese Arbeit während des Tippens passiert. Selbst wenn jede einzelne Operation "nur" einige Millisekunden braucht, ist das genau der Pfad, bei dem kleine CPU-Spitzen sofort als stockende Suche auffallen.

### Saubere Behebung

- SQL und Plugin-Zugriffe beibehalten
- danach nur rohe Result-Sets an einen `SearchPostprocessingWorker` übergeben
- dort erledigen:
  - Normalisierung
  - Candidate-Building
  - Merge
  - Ranking
  - Sortierung
  - finale DTO-Erzeugung
- iNat- und Wiki-HTTP-Responses zuerst als `bodyBytes` entgegennehmen und JSON-Decoding im Worker machen

Optionaler nächster Schritt:

- mehr Ranking direkt in SQL drücken, damit weniger Dart-Postprocessing nötig ist

Wichtiger Architekturpunkt:

- Ein Worker pro Keystroke wäre falsch
- besser ist ein langlebiger Search-Worker oder ein einfacher Pool mit Cancellation-Token/Generation-ID

## 4. Species-Hydration und Mapping großer Ergebnismengen ist ein Hauptkandidat

### Fundstellen

- `lib/catalog/repository/species_repository.dart:257-345`
- `lib/catalog/repository/species_repository.dart:419-475`
- `lib/catalog/repository/species_repository.dart:614-930`

### Warum das ein Problem ist

`SpeciesRepository.getSpecies()` macht nicht nur DB-Lookups, sondern danach viel Dart-Arbeit:

- Species-Maps in Domain-Objekte transformieren
- Common Names mergen
- Classification mappen
- Traits laden und mappen
- Regions laden und mappen
- String-Splitting, Normalisierung und Deduplizierung

Das ist unkritisch für ein einzelnes Species-Detail. Es wird aber teuer bei:

- Watchlist
- Flashcard-Batches
- größeren Decks
- Enrichment-Läufen

Die DB-Queries selbst blockieren den UI-Thread nicht im klassischen Sinn, aber das komplette Hydratisieren der Rückgabedaten läuft anschließend wieder im Main-Isolate.

### Saubere Behebung

- `sqflite` auf dem Main-Isolate belassen
- rohe Query-Resultate in transportfähige DTOs überführen
- DTO-Bündel an einen `SpeciesHydrationWorker` schicken
- dort mappen:
  - `Map<String, dynamic>` -> kompakte Species DTOs
  - Common-Name-Merge
  - Classification-Aufbau
  - Trait-/Region-Merge
- erst ganz am Ende zurück in app-nahe Modelle konvertieren

Noch sauberer wäre zusätzlich:

- Roundtrips reduzieren
- `_loadSpeciesRowsByIds()` nicht noch einmal denselben Datensatz laden, wenn der erste Query-Pfad schon fast alles geliefert hat
- mehr Voraggregation direkt im SQL machen

Der größte Gewinn kommt hier aus der Kombination:

- weniger DB-Roundtrips
- weniger Dart-Mapping auf dem UI-Isolate

## 5. Flashcards und Watchlist lösen zu viel Arbeit auf einmal aus

### Fundstellen

- `lib/application/species_media/species_media_service.dart:49-68`
- `lib/learning/service/flashcard_service.dart:24-43`
- `lib/learning/service/flashcard_service.dart:116-125`
- `lib/catalog/watchlist/watchlist_page.dart:40-60`
- `lib/shared/service/image_service.dart:219-245`

### Warum das ein Problem ist

Mehrere UI-Pfade feuern breite `Future.wait(...)`-Fächer:

- alle Species einer Watchlist
- alle Flashcards eines Review-Batches
- jeweils inklusive Species-Load, Foto-Auflösung und teilweise Downloads

Dazu kommen synchrone File-System-Aufrufe in `ImageService`:

- `dir.existsSync()`
- `createSync()`

Sobald viele Bilder oder viele Species gleichzeitig verarbeitet werden, steigt die Last auf dem Main-Isolate unnötig an. Das ist nicht nur ein Threading-Thema, sondern auch ein Scheduling-Thema: zu viel Arbeit parallel, ohne Priorisierung nach Sichtbarkeit.

### Saubere Behebung

- `Future.wait(...)` in diesen Pfaden durch begrenzte Parallelität ersetzen
- vorhandene Helfer wie `runWithConcurrency(...)` konsequent nutzen
- Bild-Download und Metadaten-Auflösung trennen
- zuerst nur das rendern, was sofort sichtbar ist
- restliche Bilder nachladen
- synchrone FS-Aufrufe durch `await dir.exists()` und `await dir.create(...)` ersetzen

Was davon in Background-Threads gehört:

- Hashing, Path-Building und größere Listen-Transformationen können in Worker
- `path_provider` und Plugin-I/O bleiben am Haupt-Isolate

In der Praxis ist hier oft wichtiger:

- weniger gleichzeitige Arbeit
- weniger Sync-I/O
- sichtbarkeitsbasierte Priorisierung

## 6. Zwei weitere Kandidaten, die eher "kritischen UI-Pfad entschlacken" als echten Isolate-Offload brauchen

### 6.1 Deck-Übersicht erzeugt unnötig viele Einzelabfragen

#### Fundstellen

- `lib/learning/decks/home_page.dart:16-25`
- `lib/learning/decks/decks_view.dart:34-64`
- `lib/learning/service/decks_service.dart:84-95`
- `lib/learning/service/decks_service.dart:180-190`

#### Warum das ein Problem ist

- `HomePage` baut bei jedem Rebuild eine neue `getAllDecks()`-Future
- `DecksService._createViewDecks()` holt pro Deck einzeln `getDeckStat(...)`

Das ist kein typischer Worker-Kandidat, aber es verursacht wiederholt unnötige Arbeit im UI-getriebenen Pfad und verschlechtert Responsiveness.

#### Saubere Behebung

- Deck-Liste cachen oder als expliziten Load-State modellieren
- Deck-Statistiken in einer einzigen Bulk-Query laden
- `Future` nicht bei jedem Build neu erzeugen

Erst wenn danach noch messbar CPU-intensive Aggregation übrig bleibt, lohnt sich ein Worker.

### 6.2 Review reschedult alle Notifications komplett

#### Fundstellen

- `lib/learning/service/flashcard_service.dart:80-105`
- `lib/shared/service/notification_service.dart:130-190`

#### Warum das ein Problem ist

Nach jedem Review:

- werden alle Flashcard-Stats geladen
- alle Fälligkeiten für bis zu 14 Tage in Dart neu gezählt
- alle Notifications komplett neu geplant

Das ist bei wenigen Karten noch ok, skaliert aber schlecht. Plugin-Calls können nicht in einen Worker, aber die aktuelle Komplett-Neuberechnung belastet trotzdem den UI-nahen Pfad.

#### Saubere Behebung

- Due-Counts per SQL aggregieren statt alle Karten nach Dart zu holen
- nur geänderte Tage neu schedulen
- wenn nötig Zähl- und Gruppierlogik in einen Worker auslagern, Plugin-Calls aber am Main-Isolate lassen

## Empfohlene Reihenfolge

1. Import/Export/QR-Serialisierung in Worker-Isolate auslagern
2. Search-JSON-Decoding und Search-Postprocessing auslagern
3. Species-Hydration in einen Mapper-Worker verschieben
4. Startpfad von `runApp()` entkoppeln
5. Flashcard-/Watchlist-Fan-out begrenzen und Sync-FS entfernen
6. N+1- und Notification-Pfade separat vereinfachen

## Mein Fazit

Ja, da ist noch deutlich Potenzial.

Der wichtigste Punkt ist aber: **nicht alles pauschal "in einen Background-Thread" schieben**. Bei Discere ist das saubere Muster:

- Plugin-I/O bleibt, wo es ist
- schwere reine Dart-Arbeit wandert in Worker-Isolates
- UI-kritische Pfade werden entkoppelt, gecacht und in kleinere Schritte zerlegt

Wenn ich das in konkrete Umsetzungsarbeit übersetzen müsste, würde ich mit **Deck-Import/Export + Suche** anfangen. Dort ist der technische Aufwand überschaubar und der UX-Gewinn wahrscheinlich sofort spürbar.
