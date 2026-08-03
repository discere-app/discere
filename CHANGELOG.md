# Changelog

All notable changes to Discere are documented in this file.


## 1.0.6 (2026-08-03)

### Features

- inform users when a species has no findable photo
- live per-item progress, percent display gated on ready
- producer-consumer cutover fuer die iNat-Enrichment-Pipeline
- add deck-level enrichment projection
- add INatWorker for the shared iNaturalist queue
- add BaseWorker for reference-image downloads
- lay groundwork for producer-consumer enrichment queue
- Referenzdatenbank wird zur Laufzeit heruntergeladen statt gebündelt
- lizenzen anzeigen
- filter reset button hinzugefügt
- iucn statur korrekt laden und anzeigen
- häufigkeits chip hinzugefügt.
- tutorial auf detail page hinzugefügt
- enrichment starten wenn spezies zu deck hinzugefügt werden
- bilder anzeigen, wenn species hinzugefügt wird
- nach Deck-Erstellung zurück zur Detailansicht navigieren
- filter erweitert
- bilder anzigen, häufigkeit anzeigen und spezies nach region filtern
- Species aus Detailansicht zu bestehenden oder neuen Decks hinzufügen
- icun status back fill implementiert
- icun status back fill implementiert
- icun status von iNaturalist anzeigen
- wikipedia summary anzeigen
- grösse auf meter genau
- Wikipedia-Link in der Species-Detailansicht
- Flashcards ohne Bild vor dem Enrichment ausblenden
- Kontinent-Zusammenfassung für weit verbreitete Arten
- WikiCommons-Bildersuche entfernt
- direkten Retry-Button für fehlgeschlagene iNaturalist-Anreicherung
- deck sourceID und updatedAt hinzugefügt
- CommonNames oder ScientificNames lernen ermöglicht
- learning modus genus hinzugefügt
- deck order added
- review mode - multiple choice
- notification zeitpunkt einstellen
- common_names anhand von region sortiert anzeigen
- lernfortschritt abhängig vom modus anzeigen
- lernmodus auf deckoverview anzeigen
- family lernmodus hinzugefügt
- show images in fullscreen and allow zoom
- app version in about_page.dart anzeigen
- tutorial hinzugefügt
- updated fsrs algorithmus und einstellung zum finetuning hinzugefügt

### Bug Fixes

- stop deck upserts from cascading away flashcard_stats
- enforce foreign keys so deck deletion cascades
- wait for async dialog instead of asserting right after pumpAndSettle
- unblock decks whose species never get iNat consent in time
- batch the v11->v12/v12->v13 migration backfills
- remove taxonomy work's unused owner_deck_id
- drop stale non-terminal job rows in v12->v13 migration
- re-check disposed state right before notifyListeners
- bound native DB opens so a wedged handle can't hang forever
- skip claiming orphaned species work, fix status fallback
- close consent leaks, stuck-deck and crash-recovery gaps
- close foreground-runner restart gap and DB-close race
- uebrige unawaited-Aufrufe gegen geschlossene DB absichern
- Multi-Line-Schleife in externes Skript auslagern
- weitere DB-Race beim Kartenwechsel abfangen
- Hintergrund-Refresh nach DB-Schliessung nicht mehr crashen lassen
- CI-Buildfehler bei fehlender Signing-Konfiguration und iOS-Deployment-Target beheben
- interaktive Bildersuche wartet nicht mehr auf Host-Cooldown
- Lernsession zeigt Karten auch, wenn kein Bild rechtzeitig geladen werden kann
- Species-Stage gibt nach mehreren erfolglosen Versuchen auf statt dauerhaft "remaining" zu bleiben
- DB-Handle beim Engine-Teardown schließen, verhindert Hänger im Splash Screen
- Endemiten in der Regionen-Sektion korrekt anzeigen
- Dismissible-Crash beim Löschen eines Decks
- future-builder bug gefixt
- taxonomy navigation korrigiert
- make enrichment work cleanup mutable and harden iNat-related tests
- make enrichment work cleanup mutable and harden iNat-related tests

### Refactoring

- drop membership pruning and forced projection reload
- split user DB migrations into per-version files
- extract user DB schema/migrations into UserDbSchema
- normalize taxonomy work and ship it in one v11->v12 migration
- drop unused onSpeciesCompleted from base image service
- DatabaseException-Handling von deck_page in FlashcardService verschieben
- Diagnostics als eigenständiges Modul mit Sink-Port
- TaxonRank-Enum ersetzt stringly-typed Rank-Switches
- iNat-Suchergebnisse und Runtime-Taxonomie-Zeilen gegen Referenz-DB auflösen als eigener Collaborator
- Review Phase 6c (1/2) – SQL ausgelagert, Serialisierung entdoppelt
- Review Phase 6b – Taxonomie-Common-Names aus EnrichmentService gelöst
- Review Phase 6a – enrichment_job_executor aufgeteilt
- Review Phase 5 – Konstruktor-Injection statt versteckter Defaults
- Review Phase 5 – Bootstrap in Slice-Wiring-Module aufgeteilt
- gemeinsame Deck-Formularsektionen für Create und Edit
- Edit-Flow unter learning/decks/edit/ gruppiert
- Review Phase 4c – DeckEnrichmentInfo auf konsumierte Felder reduziert
- Review Phase 4b – EnrichmentStateStyle extrahiert, deck_card aufgeteilt
- Review Phase 4a – edit_deck_page in fokussierte Dateien aufgeteilt
- Review Phase 3 – external-Slice für Dritt-API-Clients
- Review Phase 2 – Enrichment-Typen in die richtige Slice-Ebene
- Review Phase 1 – Permission-Helper, SQL-Härtung, strengere Lints
- datenbank einheitlich injected
- kleinere code-duplikate im enrichment/learning-modul bereinigt
- enrichment-spezifischen code aus shared-modul entfernt
- presenter optimiert
- sqls optimiert
- enrichment bug gefixed
- claud.md architketur aktuallisiert

### Performance

- claim cover jobs with a targeted query
- drop per-species full-table scans and redundant allocations
- Concurrency-Limit für Watchlist-/Flashcard-Bilderauflösung
- Notification-Reschedule-Performance optimiert
- load remote decks via a single combined index instead of N+1 requests
- kleine optimierungen
- enrichment dublikat species direkt filtern, nicht über cache auflösen
- enrichment dublikat species direkt filtern, nicht über cache auflösen
- Improve Android enrichment UX and background resilience

### Documentation

- describe current design without references to removed executor
- document only current state in enrichment docs
- adapted documentation to new implementation
- Community-Dokumente für Open-Source-Veröffentlichung ergänzen
- Dokumentation aufgeräumt
- update hosting references from Codeberg to GitHub
- Commit-Messages ohne KI-Attribution festgeschrieben
- updated documentation

### Tests

- add an end-to-end integration test for the photo-gaps flow
- cover updateDeck and deck_config for the cascade fix
- cover cross-deck ordering of the shared iNat queue
- verbleibende ungeschuetzte Assertions in export_import/review_flow absichern
- waitForCondition/waitForAbsence fuer zwei weitere Reload-Race-Faelle
- waitForFinder an drei weiteren Stellen mit demselben Reload-Race
- auf tatsaechliches Erscheinen von Widgets warten statt nur auf pumpAndSettle
- Timing-Budgets in safePumpAndSettle/dismissDownloadDialog verdoppeln
- lizenzen anzeigen
- Integrationstests an vereinheitlichte Rang-Icons angepasst
- tests erweitert und geflickt
- Test-Layout auf 1:1-Slice-Spiegelung vereinheitlicht
- tests erweitert
- tests geflickt
- integration test gefixt
- integration test gefixt
- integration test gefixt
- integration test angepasst
- enrichment test geflickt

### CI/CD

- Integrationstests nach fachlichen Bereichen shardden
- Integrationstests pro Datei isoliert statt gebuendelt ausfuehren
- pixel_6-Hardwareprofil fuer die Test-AVD setzen
- aktuelle Action-Versionen, ABI-restriktiver Pre-build fuer Integrationstests
- Gradle-Compile vor Emulator-Start entkoppeln, Gradle-Cache ergänzen

### Chores

- add version bump and changelog generation scripts
- Pipeline in parallele Jobs für Unit- und Android-Integrationstests aufteilen
- Repos zu discere-app-Organisation umgezogen
- AGPLv3 statt CC BY-NC 4.0 für den App-Code
- task in github issues überführt
- publish reference-db releases via gh CLI
- point app to GitHub instead of Codeberg
- version erhöht
- icon und farbe für überklasse geändert
- deutsche Texte überarbeitet
- labeltext aus textfeld entfernt
- Decks-Overview - Textüberlauf korrigiert
- confirmDiscardChanges-Dialog bei EditPage, Enable `android:enableOnBackInvokedCallback` in AndroidManifest.xml
- MainScreenPage nutzt jetzt IndexedStack statt der Index-basierten body
- navigation optimiert
- navigation optimiert
- image carousel besser sichtbar
- version erhöht
- landscape modus blockiert
- text korrigiert
- version erhöht
- version erhöht
- tasks neu priorisiert
- migration für deckID und updatedAt
- alter task entfernt
- enrichment job tabelle aufräumen
- enrichment notification und dialoge optimiert
- fix architecture flaw
- android build tools updated
- increased version
- misc dependencies updated
- misc dependencies updated
- misc dependencies updated
- path_provider updated
- image_picker updated
- flutter_local_notifications updated
- file_picker updated
- connectivity_plus updated
- new release
- navigation in detail ansicht anzeigen
- updated iucn strategy
- version erhöht
- div. übersetzungen hinzugefügt
- hinweis text für enrichment klarer formuliert
- hinweis text für enrichment klarer formuliert
- version erhöht
- erkärung zu enrichment states hinzugefügt
- text status angepasst im enrichtment
- increased version
- vertikaler design überlauf korrigert
- enrichment weiter verbessert
- enrichment weiter verbessert
- enrichment weiter verbessert
- enrichment weiter verbessert
- further improved background enrichment
- diagnostics introduced
- diagnostics introduced

### Other

- stille Tageslimits für neue Karten / Reviews entfernt
- textfarbe korrigiert
- commonname icon geändert
- Nicht kuratierte Subregionscodes auf der Detailseite ausblenden
- Keep other downloads in a batch when one image's directory creation fails
- Document the current iNaturalist enrichment pipeline and link it from the architecture overview
- Add design notes on informing users when no photo was found for a species
- Mark iNat/reference photo stages complete only once the image actually saved locally, not once the URL was resolved
- UI-Karten/Bild-Platzhalter/Info-Banner konsolidiert, Ocean-Theme-Farbrollen vollständig gesetzt
- Abfragemodus in Lerneinstellungen zusammenführen
- Start-Button: Fälligkeit statt Fortschritt, Stats-Refresh nach Lern-Flow
- Rang-Icons vereinheitlicht (Deck-Button, Systematik, Suche)
- Bugfix:Handle terminal "taxon not found" state in iNaturalist enrichment
- flashcard front - bild grösser, button entfernt, negative space entfernt
- Trim onboarding tutorials and fix skip-button overlap

Format follows [Keep a Changelog](https://keepachangelog.com/).
