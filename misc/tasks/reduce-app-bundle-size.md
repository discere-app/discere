# Reduce App Bundle Size

**Kategorie:** Improvement · **Priorität:** Hoch (dringlicher geworden) · **Komplexität:** Mittel · **Status:** In Umsetzung — siehe [reference-db-target-architecture.md](reference-db-target-architecture.md)

## Kurzbeschreibung

Der Android App Bundle war beim Schreiben ~94 MB — mittlerweile ist allein
`assets/database/discere_reference.db` auf **384 MB** angewachsen (verifiziert
im aktuellen Repo, vs. 285 MB, die noch in `ui-thread-offloading-analysis.md`
vom 2026-04-19 genannt wurden). Die Referenzdatenbank dominiert die
Bundle-Größe damit klar und das Problem hat sich seit Erstellung dieses
Tasks verschärft statt entschärft.

**Update:** Statt Kompression/Optimierung des gebundelten Assets wird die
Referenzdatenbank komplett aus dem App-Bundle entfernt und stattdessen zur
Laufzeit heruntergeladen (Details: [reference-db-target-architecture.md](reference-db-target-architecture.md)).
Das löst dieses Bundle-Size-Problem direkt an der Wurzel, statt es nur zu
lindern. Die übrigen Punkte unten (native Libraries, Dart-AOT, Fonts) bleiben
als separate, kleinere Nachfolge-Optimierungen relevant, sobald die
Referenz-DB nicht mehr dominiert.

## Technisch notwendig

- `flutter build appbundle --release --analyze-size` für Size-Report.
- Keine externen Dienste — reine Asset-/Build-Optimierung.

## Lösungsidee

- Size-Report analysieren: Asset-Anteil, native Libraries pro ABI, Dart-AOT-
  Snapshot, Package-Code-Größe.
- Prüfen, ob unnötige Spalten/Daten in `discere_reference.db` entfernt werden
  können (ETL-seitig).
- Referenzdatenbank komprimiert ausliefern und beim ersten Start entpacken,
  falls Startup-Kosten akzeptabel sind.
- Breite Asset-Includes (`assets/`) durch explizite Pfade ersetzen.
- Native Dependencies/Plugins auf vermeidbaren Plattform-Payload prüfen.
- Nicht benötigte Google-Fonts/optionale Dependencies entfernen.

## Probleme / offene Fragen

- 384 MB DB-Wachstum seit der letzten Messung deutet auf zusätzliche
  ETL-Daten hin (z. B. neue Felder/Regionen) — sollte zuerst untersucht
  werden, was konkret gewachsen ist, bevor an Kompression gearbeitet wird.
- Kompression/Entpacken beim ersten Start kann die bereits kritische
  Bootstrap-Phase verlängern (siehe
  [ui-thread-offloading-analysis.md](ui-thread-offloading-analysis.md),
  Punkt 1 — App wartet aktuell schon komplett auf DB-Kopie vor `runApp()`).
  Beide Tasks sollten koordiniert angegangen werden.
- Offline-Suche und Startup-Verhalten müssen nach jeder Packaging-Änderung
  weiter funktionieren; Integration-Smoke-Test muss grün bleiben.

## Akzeptanzkriterien

- Hauptverursacher der Bundle-Größe dokumentiert.
- Vorher/Nachher-Bundle-Größen erfasst.
- Offline-Start und Referenz-Suche funktionieren unverändert.
