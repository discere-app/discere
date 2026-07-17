# Diagnostics Mode: Optional Error Log Persistence

**Kategorie:** Feature · **Priorität:** Niedrig · **Komplexität:** Mittel · **Status:** Backlog, weiterhin relevant

## Kurzbeschreibung

Ein zukünftiger Diagnostics/Developer-Mode mit explizitem UI-Toggle, der
lokale Persistenz ausgewählter Log-Statements aktiviert (`Logger.error`,
optional `warn`), um schwer reproduzierbare Fehler zu fassen (Android
Background-Fehler, temporäre API-Ausfälle, geräte-spezifische Bugs).
Standardverhalten bleibt unverändert (keine persistenten Debug-Logs).

## Technisch notwendig

- Erweiterung von `Logger` um einen optionalen Diagnostics-Sink.
- Lokale Tabelle (User-DB) für gepufferte Log-Einträge, Ring-Buffer/bounded
  size.
- Neuer UI-Toggle + sichtbarer Indikator, wenn aktiv.

## Lösungsidee

1. `Logger` um optionalen Sink erweitern, der nur bei aktivem Diagnostics-Mode
   schreibt.
2. Filter nach Level (`error`, optional `warning`) und Kategorie (`network`,
   `background`, `enrichment`).
3. Persistierte Einträge (Timestamp, Scope, Level, Message, optional
   Stacktrace bei `error`) in Diagnostics-Screen anzeigen.
4. Export als kompakter lokaler Report.
5. Automatisches Abschalten des Sinks, wenn der Toggle deaktiviert wird.

## Probleme / offene Fragen

- Muss strikt lokal bleiben (kein Remote-Reporting) — Datenschutz-Anforderung.
- Ring-Buffer-Größe und Rotationsstrategie noch nicht festgelegt.
- Kein bestehender Diagnostics-Screen vorhanden, an den sich das anhängen
  ließe — müsste neu gebaut werden.
