# Architecture Improvement Tasks

**Kategorie:** Improvement · **Status:** Teilweise erledigt, Rest gegen aktuellen Code verifiziert offen

Companion zu [`misc/architecture-overview.md`](../architecture-overview.md).
Ursprünglich vom 2026-03-31, jetzt gegen den aktuellen Code-Stand (Feature-
Slice-Struktur `lib/{app,catalog,enrichment,learning,shared}/`) geprüft und
aktualisiert. Alte Pfadangaben (`lib/service/`, `lib/ui/`, `lib/persistence/`)
existieren nicht mehr und wurden korrigiert oder als erledigt markiert.

## Übersicht

| # | Task | Priorität | Komplexität | Status |
|---|---|---|---|---|
| 1 | Dead Code entfernen | Niedrig | Niedrig | Teilweise erledigt — Rest offen |
| 2 | Notification-Reschedule-Performance | Hoch | Niedrig | Offen (verifiziert) |
| 3 | `FutureBuilder`-Rebuild-Bugs | Hoch | Mittel | Offen (verifiziert) |
| 4 | Repository-Interfaces einführen | Mittel | Mittel | Offen |
| 5 | Serialisierung vereinheitlichen | Niedrig | Mittel | Ungeprüft, vermutlich noch offen |
| 6 | `DatabaseHelper` aus statischem Singleton lösen | Mittel | Mittel | Offen (verifiziert, weiterhin statisch) |
| 7 | Typisiertes Routing (`go_router`) | Niedrig | Mittel | Offen (verifiziert, weiterhin `Navigator.push`) |
| 8 | `Result`-Type für Fehlerbehandlung | Niedrig | Mittel | Ungeprüft |
| 9 | Notification-Scheduling aus `FlashCardService` extrahieren | Niedrig | Niedrig | Offen |
| 10 | Feature-First-Modulstruktur | — | — | **Erledigt ✅** — bereits umgesetzt |

---

## Task 1: Dead Code entfernen

**Priorität:** Niedrig · **Komplexität:** Niedrig · **Status:** Teilweise erledigt

### Kurzbeschreibung
Ursprünglich 5 Punkte. Verifiziert: `SpacedRepetitionService` (Legacy SM-2)
und `FlashCardStat.easeFactor` sind bereits vollständig aus dem Code entfernt.
Weiterhin vorhanden und tot:
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

**Priorität:** Hoch · **Komplexität:** Mittel · **Status:** Offen (verifiziert)

### Kurzbeschreibung
`lib/learning/decks/home_page.dart:33` ruft `decksService.getAllDecks()`
direkt im `Consumer`-Builder auf — bei jedem `notifyListeners()` entsteht ein
neues `Future`, was `DecksView`/`FutureBuilder` von vorne starten lässt
(Spinner-Flash). Gleiches Muster potenziell in `deck_card.dart` für
Pro-Card-Stats.

### Technisch notwendig
Keines.

### Lösungsidee
`_HomePageState` das Future in `initState()` cachen, nur bei echten
Änderungen (z. B. über einen expliziten Listener/Callback) neu erzeugen statt
bei jedem Widget-Rebuild. Für `deck_card.dart`: Stats im Parent vorladen und
als Konstruktor-Parameter durchreichen statt pro Karte einzeln zu fetchen.

### Probleme
`HomePage` ist inzwischen ein `StatefulWidget` mit eigenem `onRefresh`-
Callback (`setState({})` bei Rückkehr von Navigation) — die Refresh-Logik
muss beim Umbau erhalten bleiben, nicht nur das Future-Caching selbst.

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

---

## Task 10: Feature-First-Modulstruktur

**Status:** Erledigt ✅

### Kurzbeschreibung
Ursprünglich vorgeschlagene Umstellung von Layer-First
(`model/`, `persistence/`, `service/`, `ui/`) auf Feature-First-Slices ist
bereits umgesetzt: der Code liegt heute unter
`lib/{app,catalog,enrichment,learning,shared}/`, jede Slice mit eigenen
`model/`, `repository/`, `service/`, UI-Dateien. Die Abhängigkeitsmatrix
zwischen Slices wird automatisch durch
`test/architecture/module_dependency_test.dart` erzwungen (siehe
`CLAUDE.md`).

### Empfehlung
Kein Handlungsbedarf mehr — Punkt kann aus aktiven Tasks gestrichen werden.
