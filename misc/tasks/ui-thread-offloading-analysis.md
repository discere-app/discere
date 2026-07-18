# UI Thread Offloading Analysis

**Kategorie:** Analyse + Improvement · **Status:** Re-verifiziert 2026-07-17 — 4 von 6 Punkten erledigt oder bewusst zurückgestellt, Rest bewusst nicht verfolgt

## Kurzbeschreibung

Discere hatte spürbares Potenzial, reine Dart-CPU-Arbeit vom UI-Isolate in
Worker-Isolates auszulagern. Plugin-/Platform-Channel-Aufrufe (`sqflite`,
`shared_preferences`, `path_provider`, `rootBundle`,
`flutter_local_notifications`) bleiben zwingend am Main-Isolate — verschiebbar
ist nur reine Dart-Arbeit: JSON/GZIP/Base64, Ranking, Merging, Mapping,
Sortierung, Hashing.

Bei der Re-Prüfung gegen den aktuellen Code (statt gegen den Stand vom
2026-04-19) zeigte sich: mehr Punkte waren bereits erledigt als erwartet,
und zwei der verbleibenden Punkte lohnen sich bei den tatsächlichen
Datenmengen in dieser App nicht (siehe Einzelpunkte 3 und 4).

## Einzelpunkte

### 1. Startpfad vor `runApp()` — Erledigt ✅
`main.dart` ruft `runApp(BootstrapApp(...))` sofort auf.
`_BootstrapAppState` rendert eine leichte `_BootstrapShell` während
`_setupCriticalServices()` hinter einem `FutureBuilder` läuft — inkl.
Status-Callback für Progress-Text, 12s-Timeout und eigenem
`_BootstrapErrorShell` mit Retry. Geht über den ursprünglichen Vorschlag
hinaus.

### 2. Import/Export/Share — Erledigt ✅
`DeckSerializationWorker` (`lib/learning/service/deck_serialization_worker.dart`)
nutzt `Isolate.run(...)` für JSON-Encode/Decode, GZIP und Base64. Wird von
`ImportExportService`, `DeckImportService` und `RemoteDeckService` genutzt.
`ShareDeckPage` cached den Export-Future bereits in `initState()` statt ihn
im `build()` neu zu erzeugen.

### 3. Search-Postprocessing — Geprüft, zurückgestellt
`BackgroundJson.decodeBytes()` (`Isolate.run` + `jsonDecode`) wird in
`inaturalist_service.dart` und `wiki_service.dart` konsequent für
HTTP-Response-Decoding genutzt — der wertvollste Teil dieses Punkts ist
also bereits erledigt. Ein Nebenfund: eine einzelne `resolveTaxon`-artige
Methode in `inaturalist_service.dart` (~Zeile 658) nutzt noch synchrones
`jsonDecode` statt `BackgroundJson` — geringe Priorität, kein Live-Suche-Pfad.

Das eigentliche Candidate-Building/Merge/Ranking in `SearchRepository` läuft
weiterhin auf dem Main-Isolate — **das lohnt sich aber nicht**:
`_referenceResultLimit = 20` pro Query begrenzt die Kandidatenmenge auf
geschätzt 100–150 rohe Einträge vor dem finalen Ranking. Reines
Dart-Mapping/Sortieren dieser Größenordnung dauert Mikrosekunden;
`Isolate.run()` kostet allein durch Spawn + Message-Passing bereits ein
paar Millisekunden Overhead. Ein Worker würde die Suche eher *langsamer*
machen, nicht schneller. Ohne konkrete Jank-Beobachtung nicht verfolgen.

### 4. Species-Hydration — Geprüft, zurückgestellt
`SpeciesRepository.getSpecies()` mapped weiterhin komplett auf dem
Main-Isolate, kein `SpeciesHydrationWorker` vorhanden. Decks/Batches sind
aber standardmäßig auf überschaubare Größen begrenzt
(`newCardsPerDay: 20`, `maxReviewsPerDay: 200` als Defaults in
`DeckConfig`) — für ein komplett neues Worker-Setup bräuchte es echte
Evidenz für spürbares Jank bei größeren Watchlists/Decks, die nirgends im
Code oder in Diagnostics-Daten zu finden ist. Premature Optimization ohne
konkreten Auslöser — zurückstellen, bis ein echter Fall auftaucht.

### 5. Flashcard-/Watchlist-Fan-out — Erledigt ✅ (Kernteil)
Der synchrone-FS-Calls-Teil (`dir.existsSync()`, `createSync()` in
`ImageService`) ist kosmetisch (Verzeichnis-Setup, kein Hot Path) und
bewusst nicht angefasst.

Der eigentlich relevante Teil war ein anderer als ursprünglich gedacht:
nicht CPU-Arbeit, sondern unbegrenzte parallele **Netzwerk-/Disk-I/O**.
`SpeciesMediaService.resolveAllWithDownload()` (Watchlist) und
`FlashcardService._createFlashCards()` (Deck-Batches) nutzten unbegrenztes
`Future.wait(...)` über alle Species gleichzeitig. Bei einer großen
Watchlist mit vielen fehlenden Bildern hätte das viele gleichzeitige
HTTP-Requests + DB-Reads ausgelöst.

**Umsetzung:** Beide Stellen nutzen jetzt die bereits vorhandene
`runWithConcurrency()`-Utility (schon in `ImageService` im Einsatz):
- `SpeciesMediaService.resolveAllWithDownload()` — `maxConcurrent: 6`
  (gleicher Wert wie `ImageService._maxConcurrentDownloads`, da hier
  ebenfalls echte Netzwerk-Downloads passieren können).
- `FlashcardService._createFlashCards()` — `maxConcurrent: 10` (nur
  Cache-Reads, kein Netzwerk, daher großzügigerer Wert).

Kein neuer Worker, keine Isolate-Infrastruktur — reine
Concurrency-Begrenzung mit bereits bestehender Utility. Verhaltensneutral
für kleine Listen, verhindert Ressourcen-Kontention bei großen.

### 6. Deck-Übersicht N+1 & Notification-Reschedule — Erledigt ✅
Deckt sich mit den bereits gefixten Tasks 2 und 3 aus
[architecture-improvements.md](architecture-improvements.md).

## Fazit

Von den ursprünglich 6 Punkten sind 4 erledigt (1, 2, 5, 6), 2 bewusst
zurückgestellt (3, 4 — kein Isolate-Overhead für Datenmengen, bei denen der
Gewinn im Rauschen verschwindet). Kein offener Punkt in diesem Dokument
mehr aktiv zu verfolgen, außer neue Evidenz für Jank bei Species-Hydration
oder Suche taucht auf.
