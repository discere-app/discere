# UI Thread Offloading Analysis

**Kategorie:** Analyse + Improvement · **Priorität:** Mittel–Hoch · **Komplexität:** gemischt (siehe Einzelpunkte) · **Status:** Aktuell (letzter Code-Check 2026-04-19), teilweise noch offen

## Kurzbeschreibung

Discere hat spürbares Potenzial, reine Dart-CPU-Arbeit vom UI-Isolate in
Worker-Isolates auszulagern. Plugin-/Platform-Channel-Aufrufe (`sqflite`,
`shared_preferences`, `path_provider`, `rootBundle`,
`flutter_local_notifications`) bleiben zwingend am Main-Isolate — verschiebbar
ist nur reine Dart-Arbeit: JSON/GZIP/Base64, Ranking, Merging, Mapping,
Sortierung, Hashing.

## Technisch notwendig

Keine externen Dienste. `compute()`/eigene Worker-Isolates, keine neuen
Packages nötig.

## Einzelpunkte (mit empfohlener Reihenfolge)

### 1. Startpfad vor `runApp()` — Priorität Hoch, Komplexität Mittel
`main()` wartet `setupServices()` komplett ab (SharedPrefs, Locale,
Notifications, Referenz-DB-Kopie aus Assets) bevor der erste Frame gerendert
wird. Referenz-DB ist mittlerweile 384 MB (siehe
[reduce-app-bundle-size.md](reduce-app-bundle-size.md) — beide Tasks
überschneiden sich hier und sollten koordiniert angegangen werden).
**Lösungsidee:** `runApp()` sofort starten, nur leichten Bootstrap-Shell
rendern; Services in `critical`/`deferred` aufteilen; DB-Kopie als expliziten
Bootstrap-Step mit Progress-Anzeige modellieren.
**Probleme:** `rootBundle`/`path_provider` bleiben am Main-Isolate — Gewinn
kommt aus Entkopplung vom ersten Frame, nicht aus `compute()`.

### 2. Import/Export/Share — Priorität Hoch, Komplexität Niedrig–Mittel
`ShareDeckPage` (`lib/learning/share/share_deck_page.dart:160-181`) erzeugt
JSON-Export direkt im `FutureBuilder`-Build. `ImportExportService`,
`DeckImportService`, `RemoteDeckService` machen JSON/GZIP/Base64 synchron am
Main-Isolate.
**Lösungsidee:** Dedizierter `DeckSerializationWorker`-Isolate für
JSON-Stringify/Parse, GZIP, Base64. `ShareDeckPage` berechnet Exportdaten
einmal in `initState()`/gecachter Future statt in `build()`.
**Probleme:** Keine bekannten — sauberster erster Schritt, da fast reine
Dart-Arbeit.

### 3. Search-Postprocessing — Priorität Mittel, Komplexität Mittel
`SearchRepository` hat bereits einen `searchQuick()`-Live-Suche-Pfad; SQL ist
gut optimiert. Aber Candidate-Building, Merge, Ranking, Sortierung, Mapping
laufen weiterhin am Main-Isolate, ebenso JSON-Decoding in
`INaturalistService`/`WikiService` direkt nach HTTP-Responses.
**Lösungsidee:** Rohe Result-Sets an `SearchPostprocessingWorker` übergeben;
HTTP-Responses zuerst als `bodyBytes` entgegennehmen, JSON-Decoding im
Worker. Ein langlebiger Search-Worker mit Cancellation-Token/Generation-ID,
nicht ein Worker pro Keystroke.
**Probleme:** Sensibel, weil es während des Tippens läuft — kleine
CPU-Spitzen fallen sofort als Ruckeln auf.

### 4. Species-Hydration — Priorität Mittel, Komplexität Mittel
`SpeciesRepository.getSpecies()` (`lib/catalog/repository/species_repository.dart:257-930`)
macht nach DB-Lookups viel Dart-Mapping (Common Names, Classification,
Traits, Regions). Unkritisch für Einzel-Detail, teuer bei Watchlist,
Flashcard-Batches, größeren Decks, Enrichment-Läufen.
**Lösungsidee:** Rohe Query-Resultate als DTOs an `SpeciesHydrationWorker`,
dort mappen, erst am Ende in App-Modelle konvertieren. Zusätzlich Roundtrips
reduzieren, mehr Voraggregation in SQL.
**Probleme:** Keine bekannten — hauptsächlich Umbauaufwand.

### 5. Flashcard-/Watchlist-Fan-out — Priorität Niedrig–Mittel, Komplexität Niedrig
Breite `Future.wait(...)`-Fächer für Watchlist-/Flashcard-Batches inkl.
Foto-Auflösung/Downloads. Zusätzlich synchrone FS-Aufrufe in `ImageService`
(`dir.existsSync()`, `createSync()`).
**Lösungsidee:** Begrenzte Parallelität statt unbegrenztem `Future.wait`
(`runWithConcurrency(...)` konsequent nutzen), Download von
Metadaten-Auflösung trennen, zuerst nur sichtbares rendern, synchrone
FS-Aufrufe durch async-Varianten ersetzen.
**Probleme:** Eher Scheduling- als reines Threading-Thema.

### 6. Deck-Übersicht N+1 & Notification-Reschedule — Priorität Niedrig, Komplexität Niedrig
Siehe [architecture-improvements.md](architecture-improvements.md) Tasks 2
und 3 — deckungsgleich mit dort bereits detaillierten Punkten
(`HomePage`-Future-Neuerzeugung pro Rebuild, komplettes
Notification-Reschedule nach jedem Review).

## Empfohlene Gesamt-Reihenfolge

1. Import/Export/QR-Serialisierung auslagern
2. Search-JSON-Decoding und Postprocessing auslagern
3. Species-Hydration in Mapper-Worker verschieben
4. Startpfad von `runApp()` entkoppeln
5. Flashcard-/Watchlist-Fan-out begrenzen, synchrone FS entfernen
6. N+1- und Notification-Pfade vereinfachen (siehe architecture-improvements.md)

## Probleme (übergreifend)

Nicht pauschal alles in Background-Threads schieben — Plugin-I/O bleibt am
Main-Isolate, nur schwere reine Dart-Arbeit wandert in Worker. Größter
erwarteter UX-Gewinn bei überschaubarem Aufwand: Deck-Import/Export + Suche.
