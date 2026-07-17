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
| [inaturalist-enrichment-strategy.md](inaturalist-enrichment-strategy.md) | Analyse + Improvement | Hoch (P0-Punkt) | gemischt | Aktuell, aktiver Referenz-Doc |
| [iucn-red-list-enrichment.md](iucn-red-list-enrichment.md) | Feature | Niedrig (bewusst Backlog) | Hoch | Backlog, gut spezifiziert |
| [species-trait-tag-taxonomy.md](species-trait-tag-taxonomy.md) | Feature | Niedrig | Mittel | Backlog, weiterhin relevant |
| [diagnostics-mode-error-log-persistence.md](diagnostics-mode-error-log-persistence.md) | Feature | Niedrig | Mittel | Backlog, weiterhin relevant |
| [deck-index-automation.md](deck-index-automation.md) | Analyse/Entscheidung | Niedrig | Niedrig–Mittel | Entschieden, kein Handlungsbedarf |
| [production-release.md](production-release.md) | Roadmap/Checkliste | — | — | **Veraltet — App bereits live** |
| [image-storage-collision.md](image-storage-collision.md) | Bugfix | — | — | **Erledigt ✅** |

## Auffälligkeiten bei der Prüfung

- **`production-release.md` ist überholt.** Die App ist bereits als v1.0.3+17
  released (Android-Signing via `key.properties` ist konfiguriert). Die
  Release-Checkliste selbst ist obsolet; die wenigen noch offenen
  Technical-Debt-Punkte daraus sind jetzt in `architecture-improvements.md`
  gespiegelt. Empfehlung: Datei archivieren oder löschen.
- **`image-storage-collision.md` ist erledigt.** Fix (URL-Hash-Filenames,
  `crypto`-Paket) ist implementiert und getestet — im Code verifiziert
  (`crypto: ^3.0.7` in `pubspec.yaml`). Kann archiviert werden.
- **`reduce-app-bundle-size.md` ist dringlicher geworden, nicht weniger.**
  Die Referenzdatenbank ist mittlerweile auf 384 MB angewachsen (zum
  Schreibzeitpunkt der ui-thread-Analyse noch 285 MB, dieser Task ging von
  einer 94-MB-Gesamt-App aus). Hochstufen.
- **`architecture-improvements.md` ist teils überholt.** Task 10
  (Feature-First-Struktur) ist bereits umgesetzt — der Code liegt heute unter
  `lib/{app,catalog,enrichment,learning,shared}/`. Die alten Pfade
  (`lib/service/`, `lib/ui/`, `lib/persistence/`) existieren nicht mehr. Task 1
  (Dead Code) ist größtenteils erledigt (SM2-Service und `easeFactor` sind
  weg), aber `lib/theme/app_theme.dart` (leere Datei) und
  `lib/theme/marine_theme/` (unreferenziert) sind immer noch da. Tasks 2, 3,
  6, 7, 9 wurden im Code gegengeprüft und sind weiterhin unverändert offen.
