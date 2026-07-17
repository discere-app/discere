# iNaturalist Enrichment — Architektur & offene Probleme

**Kategorie:** Analyse (Architektur-Referenz) + Improvement-Punkte · **Status:** Aktuell (Stand 2026-05-23), aktiver Referenz-Doc

## Kurzbeschreibung

Nach Erstellen/Importieren eines Decks reichert Discere jede Species im
Hintergrund mit iNaturalist-Fotos und mehrsprachigen Volksnamen an
(sechsstufige Pipeline: `cover → nameResolution → base → inatPrimary →
names → inatBackfill`, koordiniert über `INatEnrichmentQueueService`,
`EnrichmentJobExecutor`, `EnrichmentService`, persistiert in
`enrichment_jobs`/`enrichment_job_stages`). Kernziel: Deck ist „ready"
(mindestens ein Bild pro Species), sobald möglich, während weitere Stages im
Hintergrund weiterlaufen. Details zur Architektur (Komponenten,
Persistenz-Modell, Execution-Modell, API-Nutzung) siehe Datei-Historie/Git —
hier nur die offenen Punkte in einheitlichem Format.

## Technisch notwendig

Keine neue externe Infrastruktur für die unten gelisteten Punkte — alles
App-interne Änderungen. Ausnahme: ETL-Verlagerung der
Taxonomie-Volksnamen (P2) würde das ETL-Schema erweitern.

## Offene Probleme (priorisiert)

### P0 — Retry-CTA für permanent fehlgeschlagene Jobs
**Priorität:** Hoch · **Komplexität:** Niedrig
**Kurzbeschreibung:** Bei `failedPermanent` ist der Retry-Pfad
(`_ManualINatEnrichmentSection` in Edit-Deck, `canTrigger = true`) technisch
funktionsfähig, aber nicht prominent genug — User muss aktiv in Edit-Deck
navigieren, um den Button zu finden.
**Lösungsidee:** Direkten „Erneut versuchen"-Button auf Deck-Card oder
Deck-Header zeigen, wenn `DeckEnrichmentInfo.hasFailedAttempt`. Ruft direkt
`scheduleDeckEnrichment` auf (kein Cancel nötig, da `ConflictAlgorithm.replace`
bereits verwendet wird).
**Probleme:** Keine — reiner UI-Exposure-Fix auf bestehender Logik.

### P1 — Taxonomy-Volksnamen als Haupt-Engpass
**Priorität:** Mittel · **Komplexität:** Hoch (keine einfache Lösung bekannt)
**Kurzbeschreibung:** `taxon_names.json` (Legacy-Endpunkt) ist häufigster
Kandidat für 429/Timeout. Bei 100 Species + 50 Taxonomie-Einheiten mit
`maxConcurrent=1`/1.1s Spacing wachsen die Volksnamen-Calls auf über zwei
Minuten.
**Lösungsidee:** Langfristig Genus/Family/Order/Class-Volksnamen ins ETL
verlagern (stabil-veränderliche Daten, gute Snapshot-Kandidaten) — passt zum
geplanten Umbau auf regionale Sprachpräferenzen. Bis dahin nur Concurrency
weiter reduzieren oder stärker cachen (`external_identifier_cache` deckt das
teilweise ab).
**Probleme:** Kein verifizierter V2-Endpunkt mit gleichwertiger Funktionalität
(Sprachzuordnung, Kandidaten je Sprache, `place_taxon_names`-Priorisierung).

### P1 — `next_attempt_at` wird nach Cooldown-Ende nicht zurückgesetzt
**Priorität:** Mittel · **Komplexität:** Niedrig
**Kurzbeschreibung:** Ein Job mit `next_attempt_at = +12h` in
`retryScheduled` bleibt bis zu 12h liegen, obwohl `HostCooldownTracker` den
Cooldown längst beendet hat — `claimNextJob` überspringt Jobs mit
zukünftigem `next_attempt_at`, unabhängig vom Cooldown-Status.
**Lösungsidee:** In `_syncCooldownStatus` (oder direkt in `claimNextJob`)
`next_attempt_at` auf `null` setzen für alle `retryScheduled`-Jobs, wenn
`cooldownJustCleared == true`.
**Probleme:** Keine bekannten — klar lokalisierter Fix.

### P1 — iOS-Background-Strategie fehlt
**Priorität:** Mittel · **Komplexität:** Hoch (keine einfache Lösung bekannt)
**Kurzbeschreibung:** Auf iOS friert die Pipeline beim App-Suspend ein, kein
Resume, kein BGTaskScheduler-Fallback.
**Lösungsidee-Optionen:** `BGProcessingTask` (iOS 13+, aber nicht
deterministisch, nur bei Ladezustand+Idle); Push-getriggertes Resume
(braucht Server-Infrastruktur); oder bewusst „iOS = Foreground only"
dokumentieren und in der UI kommunizieren.
**Probleme:** Alle technischen Optionen sind entweder unzuverlässig oder
brauchen neue Server-Infrastruktur — pragmatischste Lösung ist vermutlich die
UI-Kommunikation statt technischer Fix.

### P2 — Taxonomy-Volksnamen ins ETL verlagern
**Priorität:** Niedrig · **Komplexität:** Hoch
**Kurzbeschreibung:** Siehe P1 oben — mittelfristige strukturelle Lösung für
den Volksnamen-Engpass.
**Probleme:** Erfordert ETL-Schema-Erweiterung, Regionalisierungs-Design
(Sprachpräferenzen pro User), Migrationsstrategie für bestehende
`runtime_common_names`-Einträge.

### P2 — Import-weites Deduplication-Modell
**Priorität:** Niedrig · **Komplexität:** Hoch
**Kurzbeschreibung:** Aktuelles Modell ist deck-zentrisch — Species in
mehreren Decks erzeugen redundante API-Calls über Deck-Import-Grenzen
hinweg (innerhalb gleichzeitig laufender Jobs verhindert
`EnrichmentWorkRepository` das bereits).
**Lösungsidee:** Import-weites `speciesWork`-Modell mit globalem
`taxonResolveMemo`, separatem `taxonomyWork`-Graph und Prioritätsscore.
Details in [Architecture Overview §4.8–4.9](../architecture-overview.md#48-target-design-import-wide-inaturalist-enrichment).
**Probleme:** Größerer struktureller Umbau, kein einfacher Fix.

### P2 — iNat-Open-Data für offline `taxon_id`-Mapping
**Priorität:** Niedrig · **Komplexität:** Hoch
**Kurzbeschreibung:** `inaturalist-open-data`-Snapshots könnten
`entity_external_ids` im ETL anreichern und Live-Taxon-Resolves auf echte
Misses reduzieren.
**Probleme:** Erfordert ETL-Integration des Open-Data-Repos; Volksnamen und
kuratierte Fotos sind im Snapshot nicht gleichwertig abgedeckt (kein
Sprachranking, keine `place_taxon_names`-Priorisierung).

## Bekannte strukturelle Einschränkung (kein einzelner Task)

Deck-zentrisches Modell + Terminal-State-Invariante (Species gilt erst als
fertig, wenn Enrichment-Daten geschrieben oder ein expliziter
No-Result-Marker gesetzt wurde) sind bewusste Architekturentscheidungen, kein
offener Bug. Verbleibende Race-Lücke bei gleichzeitigem Batch-Zugriff zweier
Executors auf dieselbe Species ist praktisch sehr unwahrscheinlich
(`maxConcurrent=1`, 1.1s Spacing) und führt zu keiner Datenkorruption
(Caches machen den zweiten Write zum No-Op).
