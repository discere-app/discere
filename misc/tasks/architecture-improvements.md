# Architecture Improvement Tasks

**Kategorie:** Improvement · **Status:** Aktiv — gegen aktuellen Code verifiziert

Companion zu [`misc/architecture-overview.md`](../architecture-overview.md).
Ursprünglich vom 2026-03-31, jetzt gegen den aktuellen Code-Stand (Feature-
Slice-Struktur `lib/{app,catalog,enrichment,learning,shared}/`) geprüft und
aktualisiert. Alte Pfadangaben (`lib/service/`, `lib/ui/`, `lib/persistence/`)
existieren nicht mehr. Bereits erledigte Punkte (Feature-First-Umbau,
SM-2-Legacy-Code, `easeFactor`) wurden aus der Liste entfernt.

## Übersicht

| # | Task | Priorität | Komplexität | Status |
|---|---|---|---|---|
| 1 | Dead Code entfernen | Niedrig | Niedrig | Offen |
| 2 | Notification-Reschedule-Performance | Hoch | Niedrig | Offen (verifiziert) |
| 3 | `FutureBuilder`-Rebuild-Bugs | — | — | Erledigt ✅ |
| 4 | Repository-Interfaces einführen | Mittel | Mittel | Offen |
| 5 | Serialisierung vereinheitlichen | Niedrig | Mittel | Ungeprüft, vermutlich noch offen |
| 6 | `DatabaseHelper` aus statischem Singleton lösen | Mittel | Mittel | Offen (verifiziert, weiterhin statisch) |
| 7 | Typisiertes Routing (`go_router`) | Niedrig | Mittel | Offen (verifiziert, weiterhin `Navigator.push`) |
| 8 | `Result`-Type für Fehlerbehandlung | Niedrig | Mittel | Ungeprüft |
| 9 | Notification-Scheduling aus `FlashCardService` extrahieren | Niedrig | Niedrig | Offen |

---

## Task 1: Dead Code entfernen

**Priorität:** Niedrig · **Komplexität:** Niedrig · **Status:** Offen

### Kurzbeschreibung
`SpacedRepetitionService` (Legacy SM-2) und `FlashCardStat.easeFactor` sind
bereits entfernt. Weiterhin vorhanden und tot:
- `lib/theme/app_theme.dart` — exakt 1 Zeile, leer/ungenutzt.
- `lib/theme/marine_theme/` (`marine_colors.dart`, `marine_theme.dart`) —
  keine Referenzen im Code gefunden, `ocean_theme/` ist die aktive Theme.

### Technisch notwendig
Keines.

### Lösungsidee
Beide Dateien/Verzeichnisse löschen.

### Probleme
Keine — reine Löschung ohne Referenzen.

---

## Task 2: Notification-Reschedule-Performance

**Priorität:** Hoch · **Komplexität:** Niedrig · **Status:** Offen (verifiziert in `lib/learning/service/flashcard_service.dart`, `reviewCard()` ruft weiterhin `notificationService.rescheduleAll(...)` auf)

### Kurzbeschreibung
Jede einzelne Kartenwiederholung triggert ein volles Notification-Reschedule:
`SELECT * FROM flashcard_stats`, `cancelAll()`, Neuplanung über 14 Tage. Bei
einer Session mit 20 Karten passiert das 20×.

### Technisch notwendig
Keines.

### Lösungsidee
`rescheduleAll` aus `reviewCard()` entfernen, stattdessen neue Methode
`rescheduleNotifications()` bereitstellen und am Ende der Review-Session
(z. B. beim Verlassen der Deck-Page) einmalig aufrufen.

### Probleme
Muss sicherstellen, dass die Neuplanung auch bei App-Kill während der Session
noch passiert (z. B. via `dispose()`).

---

## Task 3: `FutureBuilder`-Rebuild-Bugs

**Status:** Erledigt ✅

### Kurzbeschreibung
`home_page.dart` und `favorites_page.dart` rufen `decksService.getAllDecks()`
bzw. `getDecks(...)` weiterhin direkt im `Consumer`-Builder auf — bei jedem
`notifyListeners()` entsteht ein neues `Future`-Objekt. Das eigentliche
Problem war aber nicht diese Neuerzeugung selbst (ein echter Refresh ist bei
Deck-Mutationen korrekt), sondern dass `DecksViewState` jede neue `Future`-
Identität als „von vorne starten" behandelte: `FutureBuilder` fiel auf
`ConnectionState.waiting` zurück, riss den kompletten `ListView`-Subtree
inkl. aller `DeckCard`-States ab (Spinner-Flash, Scroll-Position-Verlust,
unnötiges Neu-Fetchen aller Pro-Card-Stats).

`deck_card.dart`s eigener `DeckStat`-Fetch war bei der Prüfung bereits
sauber (Future wird in `initState()` gecacht und nur bei
`deck.id`-Änderung in `didUpdateWidget` neu geholt) — dieser Teil des
ursprünglichen Befunds war bereits veraltet.

### Umsetzung
Fix in `lib/learning/decks/decks_view.dart` (`DecksViewState`), da
`DecksView` die gemeinsame Basis von `HomePage` und `FavoritesPage` ist:
ein `_lastDecks`-Cache hält die zuletzt erfolgreich geladene Liste. Der
Spinner erscheint nur noch beim allerersten Laden (`_lastDecks == null`);
bei jedem weiteren `futureDecks`-Wechsel bleibt die vorhandene Liste sichtbar
und wird erst beim Abschluss des neuen Futures ausgetauscht — kein
Teardown, keine Scroll-Position-Verluste, kein unnötiges Re-Fetching.
`home_page.dart`/`favorites_page.dart` selbst mussten nicht angefasst
werden, da der Fix am gemeinsamen Ort ansetzt.

### Tests
`test/ui/decks_view_stale_while_loading_test.dart` (neu): verifiziert, dass
die alte Liste während eines laufenden Refreshs sichtbar bleibt und dass der
Spinner nur beim ersten Laden erscheint.

### Verwandter Fund: gleiches Muster in `watchlist_page.dart`
Beim Durchsuchen des Codes nach weiteren Vorkommen desselben Bugs (auf
Nachfrage) fiel `lib/catalog/watchlist/watchlist_page.dart` auf: Entfernen
einer Species per Swipe riss dort ebenfalls die komplette Liste ab. Dort
zusätzlich eine optimistische Entfernung aus dem `_lastFlashcards`-Cache in
`_onDismissed` eingebaut, damit das gerade weggewischte Item während des
Nachladens nicht kurz wieder auftaucht.

Dabei einen echten Flutter-Fallstrick gefunden, der beide Fixes betrifft:
`FutureBuilder`s `AsyncSnapshot` behält beim Wechsel auf eine neue Future im
`ConnectionState.waiting`-Zustand die **Daten der vorherigen Future**
(`AsyncSnapshot.inState()` kopiert `data`/`error` mit rüber). Ein reines
`if (snapshot.hasData)`-Check kann also nicht zwischen „frisches Ergebnis"
und „Restdaten der gerade ersetzten Future" unterscheiden — es muss
zusätzlich `snapshot.connectionState == ConnectionState.done` geprüft
werden. In `watchlist_page.dart` führte das ohne den zweiten Check dazu,
dass die stale Waiting-Snapshot-Daten die optimistische Entfernung
überschrieben und den gerade entfernten Eintrag zurückbrachten — Crash
(„A dismissed Dismissible widget is still part of the tree."), reproduziert
und verifiziert per Integrationstest auf echtem Android-Emulator
(`integration_test/watchlist_test.dart`). In `decks_view.dart` war derselbe
Fehler unschädlich (kein optimistisches Update dort), wurde aber aus
Konsistenzgründen ebenfalls korrigiert.

Regressionstest: `test/ui/watchlist_dismiss_stale_data_test.dart`.

---

## Task 4: Repository-Interfaces einführen

**Priorität:** Mittel · **Komplexität:** Mittel · **Status:** Offen (keine `*RepositoryBase`-Abstraktionen im Code gefunden)

### Kurzbeschreibung
Services hängen an konkreten Repository-Klassen (`DeckRepository`,
`FlashCardStatRepository`, `SpeciesRepository`, ...). Unit-Tests brauchen
entweder echtes SQLite (`sqflite_ffi`) oder fragile Mockito-Mocks auf
konkreten Klassen.

### Technisch notwendig
Keines — reine Dart-Interface-Extraktion.

### Lösungsidee
Pro Repository ein abstraktes Interface extrahieren (`DeckRepositoryBase`,
`FlashCardStatRepositoryBase`, ...), Services auf den abstrakten Typ
umstellen. Ermöglicht schnelle, isolierte Unit-Tests mit Fake-Repositories.

### Probleme
Größerer mechanischer Umbau über viele Dateien — sollte in einem fokussierten
PR ohne Business-Logik-Änderungen passieren.

---

## Task 5: Serialisierung vereinheitlichen

**Priorität:** Niedrig · **Komplexität:** Mittel · **Status:** Nicht gegen aktuellen Code geprüft, ursprüngliches Problem vermutlich weiterhin vorhanden

### Kurzbeschreibung
Drei parallele Serialisierungsstrategien: `json_serializable` (`BaseDeck`,
`CreateDeck`), manuelle `_toMap`/`_fromMap` in Repositories, manuelle
`fromMap`-Factories (`Picture`, `Species`). Führt zu Inkonsistenzen, wenn ein
Modell geändert wird.

### Technisch notwendig
Keines.

### Lösungsidee
Konvention festlegen und dokumentieren: `json_serializable` für JSON/API,
manuelle Mapper bleiben für SQL-Spalten (unterschiedliche Zwecke, nicht
austauschbar). Doppelte manuelle `toJson`/`fromJson` entfernen, wo
`json_serializable` das bereits abdeckt.

### Probleme
Muss vor Umsetzung neu gegen den aktuellen Code verifiziert werden — evtl.
seit März bereits teilweise vereinheitlicht.

---

## Task 6: `DatabaseHelper` aus statischem Singleton lösen

**Priorität:** Mittel · **Komplexität:** Mittel · **Status:** Offen (verifiziert — `lib/shared/persistence/database_helper.dart` ist weiterhin eine Klasse mit statischen Feldern/Gettern)

### Kurzbeschreibung
`DatabaseHelper` hält globalen mutable State über statische Felder.
Repositories greifen über statische Getter zu (`DatabaseHelper.userDb`) statt
über Konstruktor-Injection. Erschwert Test-Isolation (parallel laufende
Tests teilen sich denselben State) und macht die Abhängigkeit unsichtbar.

### Technisch notwendig
Keines.

### Lösungsidee
`DatabaseHelper` zu einer regulären Instanzklasse machen, als Provider in
`bootstrap_app.dart` registrieren, Repositories nehmen sie über den
Konstruktor entgegen statt über statischen Zugriff.

### Probleme
Foundational Refactor, betrifft praktisch jedes Repository — als einen
fokussierten PR mit rein mechanischen Änderungen durchführen, volle
Integration-Test-Suite vorher/nachher laufen lassen.

---

## Task 7: Typisiertes Routing (`go_router`)

**Priorität:** Niedrig · **Komplexität:** Mittel · **Status:** Offen (verifiziert — weiterhin `Navigator.push`/`Navigator.of(context).push` im Code, z. B. `lib/app/settings_page.dart`, `lib/app/main_screen_page.dart`)

### Kurzbeschreibung
Navigation läuft durchgehend imperativ über `Navigator.push`. Keine
Routennamen, keine typsichere Parameterübergabe, kein deklaratives
Deep-Linking (Notification-Handling in `MainScreenPage` ist hart auf
`selectedIndex = 0` codiert).

### Technisch notwendig
Package `go_router`.

### Lösungsidee
Zentrale Routen-Konfiguration mit `GoRouter`, `ShellRoute` für die
Hauptnavigation, typisierte Parameter (z. B. `/deck/:id`). Deep-Link von
Notifications darüber auflösen.

### Probleme
~20 Call-Sites müssen umgestellt werden; Navigations-Assertions in
Integration-Tests müssen angepasst werden.

---

## Task 8: `Result`-Type für Fehlerbehandlung

**Priorität:** Niedrig · **Komplexität:** Mittel · **Status:** Nicht gegen aktuellen Code geprüft

### Kurzbeschreibung
Uneinheitliche Fehlerbehandlung: manche Services werfen `AppException`,
andere geben `null` zurück, andere schlucken Fehler still mit `debugPrint`.
Kein konsistentes Muster, wie Services Fehler an die UI melden.

### Technisch notwendig
Keines.

### Lösungsidee
`Result<T>` Sealed-Class (`Success`/`Failure`) einführen, zunächst als Pilot
in `RemoteDeckService` und `ImportExportService`, bei Bewährung auf weitere
Services ausweiten.

### Probleme
Muss vor Umsetzung neu gegen aktuellen Code verifiziert werden, welche
Services das Problem tatsächlich noch haben.

---

## Task 9: Notification-Scheduling aus `FlashCardService` extrahieren

**Priorität:** Niedrig · **Komplexität:** Niedrig · **Status:** Offen — hängt mit Task 2 zusammen

### Kurzbeschreibung
`FlashCardService` kennt sowohl Flashcard-Review-Logik als auch
Notification-Rescheduling inkl. hartcodierter Werte (`preferredHour: 19`,
deutscher Fallback-Text `'Zeit zum Üben'` — Lokalisierungsbug für
englischsprachige User, falls `notificationTitle` nicht übergeben wird).

### Technisch notwendig
Keines.

### Lösungsidee
`NotificationService`-Abhängigkeit aus `FlashCardService` entfernen, Session-
Koordinator (z. B. an der UI/Service-Grenze) ruft `reviewCard()` pro Karte und
am Sitzungsende `notificationService.rescheduleAll()` separat auf — passt
direkt mit Task 2 zusammen (beides gemeinsam umsetzen).

### Probleme
Keine über die von Task 2 hinausgehenden.
