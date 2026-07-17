# Deck Index Automation

**Kategorie:** Analyse/Entscheidung · **Priorität:** Niedrig · **Komplexität:** Niedrig (aktuelle Lösung) / Mittel (Cloudflare-Option) · **Status:** Entschieden, kein Handlungsbedarf

## Kurzbeschreibung

`RemoteDeckService.fetchRemoteDecks()` liest eine kombinierte
`data/decks/index.json` aus dem `discere-data`-Repo (Codeberg) statt N+1
Einzelanfragen. Die Index-Datei wird von `scripts/build_deck_index.py`
generiert. Offene Frage war nur: **wer/was führt dieses Skript aus und
pusht das Ergebnis**, da `main` geschützt ist und kein CI-Runner angebunden
ist.

## Technisch notwendig (bei Automatisierung)

- Für Option „Forgejo Actions": ein erreichbarer Self-hosted-Runner (z. B. NAS,
  muss nicht 24/7 laufen — Codeberg queued Jobs serverseitig).
- Für Option „Cloudflare Worker Cron Trigger": Cloudflare-Account, Codeberg
  Personal Access Token (Secret, gescoped auf `discere-data`), Worker mit
  `scheduled`-Handler, der die Codeberg Contents API liest/schreibt
  (SHA-basierte optimistische Concurrency).

## Lösungsidee (aktuell umgesetzt)

Manuelles Maintainer-Skript `discere-data/scripts/sync_index.sh`: pullt
`main`, führt `build_deck_index.py` aus, committet/pusht bei Änderungen.
Keine Infrastruktur nötig, funktioniert heute. Vertretbar, weil jeder Merge
auf `main` ohnehin manuelle Maintainer-Review erfordert — ein zusätzlicher
manueller Schritt fällt nicht ins Gewicht.

## Probleme / Trigger für Revisit

- Risiko: Vergessen, das Skript nach einem Deck-Merge auszuführen.
- Sollte neu bewertet werden, wenn:
  - die Deck-Beitragsfrequenz deutlich steigt,
  - `discere-data` externe Contributor bekommt, die nicht auf den Maintainer
    warten sollen,
  - der IUCN-Proxy (siehe [iucn-red-list-enrichment.md](iucn-red-list-enrichment.md))
    gebaut wird — dann ließe sich der Cron-Job im selben Worker-Projekt
    mitnehmen (zwei Handler: `fetch` für IUCN, `scheduled` für den Index),
    nicht zwingend, aber quasi kostenlos huckepack.
