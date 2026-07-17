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
| 2 | Notification-Reschedule-Performance | — | — | Erledigt ✅ |
| 3 | `FutureBuilder`-Rebuild-Bugs | — | — | Erledigt ✅ |
| 4 | Repository-Interfaces einführen | Mittel | Mittel | Offen |
| 5 | Serialisierung vereinheitlichen | Niedrig | Mittel | Ungeprüft, vermutlich noch offen |
| 6 | `DatabaseHelper` aus statischem Singleton lösen | — | — | Umbewertet — Kern zurückgestellt, Konsistenz-Fix erledigt ✅ |
| 7 | Typisiertes Routing (`go_router`) | Niedrig | Mittel | Offen (verifiziert, weiterhin `Navigator.push`) |
| 8 | `Result`-Type für Fehlerbehandlung | Niedrig | Mittel | Ungeprüft |
| 9 | Notification-Scheduling aus `FlashCardService` extrahieren | Niedrig | Niedrig | Weitgehend erledigt |

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

**Status:** Erledigt ✅ (inkl. Task 9, siehe unten)

### Kurzbeschreibung
Jede einzelne Kartenwiederholung triggerte ein volles Notification-Reschedule:
`SELECT * FROM flashcard_stats`, `cancelAll()`, Neuplanung über 14 Tage. Bei
einer Session mit 20 Karten passierte das 20×.

### Umsetzung
`FlashcardService.reviewCard()` (`lib/learning/service/flashcard_service.dart`)
macht jetzt nur noch die FSRS-Bewertung + Persistenz — keine
Notification-/Permission-Calls mehr, und die `notificationTitle`/
`notificationBodyBuilder`-Parameter sind komplett weg (das war zugleich
Task 9: Notification-Concern raus aus dem Review-Domain-Code).

`DeckPageState` (`lib/learning/flashcard/deck_page.dart`) übernimmt jetzt die
Session-Koordination:
- `requestPermissions()` einmal in `initState()` statt einmal pro Karte.
- Beim Graden einer Karte (`_gradeCurrentCard`) wird nur noch ein Flag
  (`_hasReviewedThisSession = true`) gesetzt und die lokalisierten
  Notification-Strings (Titel/Body) zwischengespeichert — `context.loc` ist
  in `dispose()` nicht mehr sicher aufrufbar, deshalb Capture schon vor dem
  `await reviewCard(...)`.
- `dispose()` ruft `rescheduleNotifications()` genau einmal auf, aber nur
  wenn in dieser Session tatsächlich mindestens eine Karte bewertet wurde.

### Probleme / bewusste Einschränkung
Bei hartem App-Kill während einer laufenden Session (nicht über Zurück-Button
oder Navigator.pop) läuft `dispose()` u. U. nicht zuverlässig — die
Neuplanung für die in dieser Session bewerteten Karten würde dann bis zum
nächsten abgeschlossenen Review-Vorgang verzögert. Dieses Risiko wurde im
Vorfeld als akzeptabel eingestuft (Option A aus der ursprünglichen Analyse).

### Tests
- `test/service/learning/flashcard_service_test.dart`: `reviewCard()` ruft
  `rescheduleAll`/`requestPermissions` nicht mehr auf; neuer Test für
  `rescheduleNotifications()` isoliert.
- `test/ui/deck_page_multiple_choice_test.dart`: zwei neue Fälle — Reschedule
  passiert genau einmal beim Verlassen der Session (nicht pro Karte), und
  gar nicht, wenn keine Karte bewertet wurde.

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

**Status:** Umbewertet — Kern-Idee zurückgestellt, Konsistenz-Lücke geschlossen ✅

### Re-Analyse (2026-07-17)
Vor der Umsetzung nochmal genau geprüft, ob die volle Umstellung
(`DatabaseHelper` → Instanzklasse + DI über `bootstrap_app.dart`, wie
ursprünglich vorgeschlagen) tatsächlich etwas bringt oder nur für Tests
relevant wäre. Befund:

- **12 von 17 Repositories hatten das gewünschte Ziel bereits erreicht** —
  ein optionales `Database`-Injection-Pattern
  (`_injectedDb ?? DatabaseHelper.userDb`), organisch entstanden, ohne dass
  `DatabaseHelper` selbst je angefasst wurde (`SpeciesRepository`,
  `EnrichmentJobRepository`, `TaxonomyRepository`, `SearchRepository`, u. a.).
- Die verbleibenden 5 (`DeckRepository`, `FlashcardStatRepository`,
  `DailyCountRepository`, `DeckConfigRepository`, `SourceRepository`) werden
  aber **nie mit echtem SQLite unit-getestet** — die zugehörigen
  Service-Tests mocken die komplette Repository-Klasse per Mockito, nicht
  `DatabaseHelper`. Der Testisolations-Nutzen einer Injection war für diese
  5 also rein hypothetisch.
- `DatabaseHelper.close()`/`.deleteUserDatabase()` — die einzigen
  testspezifischen Notausgänge der Klasse — werden ausschließlich von
  `integration_test/` genutzt, nirgends in Produktionscode, und funktionieren
  nachweislich (auf echtem Android-Emulator verifiziert).
- Fachlich ist ein echter Singleton hier korrekt, nicht nur bequem: es gibt
  genau eine Reference-DB-Datei und eine User-DB-Datei pro Installation.

**Schluss:** Die volle Umstellung von `DatabaseHelper` selbst auf eine
Instanzklasse + DI in `bootstrap_app.dart` bringt aktuell keinen
Produktionsnutzen, der nicht schon anderweitig gelöst ist — der Blast
Radius (17 Dateien + `bootstrap_app.dart` + alle Integration-Tests) steht in
keinem Verhältnis zum Nutzen. **Wurde bewusst nicht gemacht.**

### Umsetzung (Konsistenz-Teil)
Da dem Nutzer die Konsistenz zwischen den Repositories wichtig ist: die 5
verbleibenden Repos auf dasselbe optionale Injection-Pattern gebracht wie
die anderen 12 — `DeckRepository`, `FlashcardStatRepository`,
`DailyCountRepository`, `DeckConfigRepository`, `SourceRepository` nehmen
jetzt alle `{Database? database}` im Konstruktor entgegen und fallen ohne
Override weiterhin auf `DatabaseHelper.userDb`/`referenceDb` zurück. Reine
Additiv-Änderung, kein Verhaltensunterschied — alle bestehenden
Null-Argument-Konstruktoraufrufe in `bootstrap_app.dart` funktionieren
unverändert.

### Probleme
Keine — mechanische, additive Änderung ohne Verhaltensänderung, durch
vollen Testlauf (500 Tests) und `flutter analyze` bestätigt.

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

**Status:** Weitgehend erledigt (im Zuge von Task 2)

### Kurzbeschreibung
`FlashcardService.reviewCard()` kannte bisher sowohl Flashcard-Review-Logik
als auch Notification-Rescheduling inkl. hartcodierter Werte
(`preferredHour: 19`, deutscher Fallback-Text `'Zeit zum Üben'` —
Lokalisierungsbug für englischsprachige User, falls `notificationTitle`
nicht übergeben wird).

### Umsetzung
`reviewCard()` macht keine Notification-Calls und keine
`notificationTitle`/`notificationBodyBuilder`-Parameter mehr — die
Session-Koordination (Permission-Request einmal pro Session,
Reschedule einmal am Sitzungsende, mit korrekt lokalisierten Strings) liegt
jetzt in `DeckPageState` (siehe Task 2). Damit tritt der
Lokalisierungsbug für den automatischen Review-Pfad nicht mehr auf — beide
Aufrufer (`DeckPage`, `settings_page.dart`) übergeben jetzt explizit
lokalisierte Strings.

### Verbleibende Lücke
`FlashcardService` behält weiterhin eine `NotificationService`-Abhängigkeit
und die Methode `rescheduleNotifications()` (inkl. dem toten deutschen
Fallback-Text als Default-Wert, falls ein Aufrufer die Strings mal nicht
übergibt). Die ursprünglich vorgeschlagene vollständige Trennung
(`NotificationService` komplett aus `FlashcardService` raus, separater
Session-Coordinator) wurde nicht umgesetzt — der praktische Schaden
(Performance, Lokalisierungsbug im Alltagspfad) ist behoben, die
architektonische Blase bleibt bestehen. Niedrige Priorität, kann bei
Bedarf separat nachgezogen werden.
