# IUCN Red List Enrichment

**Kategorie:** Feature · **Priorität:** Niedrig (bewusst Backlog) · **Komplexität:** Hoch · **Status:** Backlog, gut spezifiziert

## Kurzbeschreibung

Discere zeigt aktuell nur FishBase/SeaLifeBase `Vulnerability`
(Übernutzungsanfälligkeit) — das ist kein offizieller Gefährdungsstatus. Der
IUCN Red List Status (`LC`/`NT`/`VU`/`EN`/`CR`/`EW`/`EX`/`DD` + Kriterien,
Bewertungsjahr, Populationstrend) ist der fachlich relevante Wert und soll
separat auf der Species-Detail-Seite angezeigt werden.

## Technisch notwendig

- IUCN Red List API-Key (persönlich, darf **nicht** in der App verschifft
  werden — clientseitige Obfuskierung erhöht nur die Reverse-Engineering-
  Kosten, keine echte Geheimhaltung).
- **Serverless-Proxy** als einzig verbleibende Option für einen öffentlichen
  Release (Offline-Batch im ETL wurde geprüft und verworfen). Kandidaten:
  - **Cloudflare Workers** (empfohlen — I/O-lastig, wenig CPU-Zeit, Free-Plan
    voraussichtlich ausreichend bis ~50k Lookups/Tag, sonst Workers Standard
    ~$5/Monat).
  - Deno Deploy, Fly.io, AWS Lambda + API Gateway als Alternativen.
  - Siehe [deck-index-automation.md](deck-index-automation.md) — falls dort
    ebenfalls ein Cloudflare Worker gebaut wird, könnte beides im selben
    Projekt laufen (zwei Handler).
- Neue Tabelle `iucn_assessment_cache` (species_id, category, criteria,
  population_trend, assessment_year, source_url, fetched_at).

## Lösungsidee

```
Flutter App → GET /iucn?species_id=... → Proxy
  → Cache-Hit? zurückgeben
  → Cache-Miss? IUCN API mit Server-Secret abfragen, normalisieren, cachen
```

Reihenfolge:
1. Lokales Datenmodell, Cache-Tabelle, Repository, Presenter, UI mit
   Seed-/Mock-Daten bauen.
2. Proxy-Provider wählen und Abuse-Controls (Allowlist auf `species_id`,
   Rate-Limit, lange Cache-TTL, Negative-Cache, optionales Tageslimit)
   implementieren, **bevor** der Endpunkt live geht.
3. App an Proxy anbinden, Fallback auf „nicht verfügbar" ohne die
   Detail-Seite zu blockieren.

## Probleme / offene Fragen

- Welcher Proxy-Provider konkret?
- Nur für User-Deck-Species oder für die gesamte Referenz-DB?
- Cache in Reference-DB, User-DB, oder beiden?
- Sollen Threat-/Habitat-/Conservation-Action-Details schon in v1 gespeichert
  werden, oder nur Category/Criteria/Trend/Jahr?
- Umgang mit Synonymen und taxonomischen Mismatches beim Scientific-Name-
  Lookup.
- Zitierhinweis für die Sources-Seite bei gecachten IUCN-Daten.
- IUCN-Lizenzbedingungen vor Release erneut prüfen (nicht-kommerzielle
  Nutzung frei, kommerziell → IBAT).
