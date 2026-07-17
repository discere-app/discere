# Tasks Overview

Kategorisierung, Priorisierung und Relevanz-Check aller Markdown-Dateien in
`misc/tasks/`. Stand der Prüfung: 2026-07-17, gegen den aktuellen Code-Stand
auf `refactoring` (App bereits live als v1.0.3+17).

Jede Datei wurde in ein einheitliches Format gebracht: Kurzbeschreibung,
technisch notwendige Voraussetzungen, Lösungsidee, offene Probleme.

## Tabelle

| Datei | Kategorie | Priorität | Komplexität | Status |
|---|---|---|---|---|
| [architecture-improvements.md](architecture-improvements.md) | Improvement | Mittel (Einzelpunkte Hoch) | gemischt | Teilweise erledigt, Rest offen |
| [reduce-app-bundle-size.md](reduce-app-bundle-size.md) | Improvement | **Hoch** | Mittel | Aktiv — dringlicher als beim Schreiben |
| [ui-thread-offloading-analysis.md](ui-thread-offloading-analysis.md) | Analyse + Improvement | Mittel–Hoch | gemischt | Aktuell, teilweise noch offen |
| [inaturalist-enrichment-strategy.md](inaturalist-enrichment-strategy.md) | Analyse + Improvement | Mittel | gemischt | Aktuell, aktiver Referenz-Doc |
| [iucn-red-list-enrichment.md](iucn-red-list-enrichment.md) | Feature | Niedrig (bewusst Backlog) | Hoch | Backlog, gut spezifiziert |
| [species-trait-tag-taxonomy.md](species-trait-tag-taxonomy.md) | Feature | Niedrig | Mittel | Backlog, weiterhin relevant |
| [diagnostics-mode-error-log-persistence.md](diagnostics-mode-error-log-persistence.md) | Feature | Niedrig | Mittel | Backlog, weiterhin relevant |
| [deck-index-automation.md](deck-index-automation.md) | Analyse/Entscheidung | Niedrig | Niedrig–Mittel | Entschieden, kein Handlungsbedarf |

## Erledigte / veraltete Einträge (entfernt)

- **`production-release.md`** — gelöscht. App ist bereits als v1.0.3+17
  released, Android-Signing konfiguriert. Die wenigen noch offenen
  Technical-Debt-Punkte daraus sind in `architecture-improvements.md`
  gespiegelt.
- **`image-storage-collision.md`** — gelöscht. Fix (URL-Hash-Filenames,
  `crypto`-Paket) implementiert und getestet, im Code verifiziert
  (`crypto: ^3.0.7` in `pubspec.yaml`).
- **Task 10 in `architecture-improvements.md`** (Feature-First-Struktur) —
  entfernt, bereits umgesetzt (`lib/{app,catalog,enrichment,learning,shared}/`).
- **SM-2-Legacy-Teil von Task 1** — entfernt, `SpacedRepetitionService` und
  `FlashCardStat.easeFactor` sind bereits aus dem Code entfernt. Verbleibende
  Dead-Code-Reste (`app_theme.dart`, `marine_theme/`) bleiben als Task 1
  bestehen.
- **P0 in `inaturalist-enrichment-strategy.md`** (Retry-CTA) — umgesetzt:
  `_EnrichmentHint` in `lib/learning/decks/deck_card.dart` zeigt bei
  `DeckEnrichmentState.failed` jetzt einen direkten Retry-Icon-Button auf der
  Deck-Card statt nur über Edit-Deck erreichbar zu sein.
- **Task 3 in `architecture-improvements.md`** (`FutureBuilder`-Rebuild-Bugs)
  — umgesetzt: `DecksViewState` in `lib/learning/decks/decks_view.dart` hält
  jetzt die zuletzt geladene Deck-Liste vor, statt bei jedem neuen Future
  (z. B. nach Deck-Mutationen) auf einen Spinner zurückzufallen und den
  ganzen `ListView`-Subtree abzureißen. Profitieren beide Nutzer von
  `DecksView`: `HomePage` und `FavoritesPage`.
- **Gleiches Muster in `lib/catalog/watchlist/watchlist_page.dart` behoben**
  (bei der Prüfung von Task 3 als verwandter Fund entdeckt): Entfernen einer
  Species per Swipe riss vorher die ganze Liste ab. Fix analog zu
  `DecksView`, plus eine optimistische Entfernung aus dem Cache in
  `_onDismissed`, damit das gerade weggewischte Item während des
  Nachladens nicht wieder auftaucht. Dabei einen echten Flutter-Fallstrick
  gefunden und global korrigiert: `FutureBuilder`s `AsyncSnapshot` behält
  beim Wechsel auf eine neue Future die *alten* Daten im `waiting`-Zustand
  bei (`AsyncSnapshot.inState()`) — ein reines `snapshot.hasData`-Check
  reicht also nicht, es muss zusätzlich `connectionState == done` geprüft
  werden. Ohne den zweiten Check hätte die stale „waiting"-Snapshot-Daten
  die optimistische Entfernung überschrieben und den entfernten Eintrag
  zurückgebracht — führte zu einem Crash
  („A dismissed Dismissible widget is still part of the tree."), verifiziert
  per Integrationstest auf echtem Emulator. Regressionstest:
  `test/ui/watchlist_dismiss_stale_data_test.dart`.
- **Task 2 in `architecture-improvements.md`** (Notification-Reschedule-
  Performance) — umgesetzt, inkl. Task 9 (Notification-Concern raus aus
  `FlashcardService.reviewCard()`). Reschedule passiert jetzt einmal am
  Ende einer Review-Session (`DeckPageState.dispose()`) statt einmal pro
  bewerteter Karte. Task 9 nur teilweise: `FlashcardService` behält die
  `NotificationService`-Abhängigkeit für `rescheduleNotifications()`,
  vollständige Trennung wäre ein separater, größerer Schritt.

## Auffälligkeiten bei der Prüfung

- **`reduce-app-bundle-size.md` ist dringlicher geworden, nicht weniger.**
  Die Referenzdatenbank ist mittlerweile auf 384 MB angewachsen (zum
  Schreibzeitpunkt der ui-thread-Analyse noch 285 MB, dieser Task ging von
  einer 94-MB-Gesamt-App aus). Hochstufen.
