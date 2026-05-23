# iNaturalist Enrichment — Architektur & offene Probleme

Stand: 2026-05-23

## Überblick

Nach dem Erstellen oder Importieren eines Decks reichert Discere jede Species
automatisch mit iNaturalist-Fotos und mehrsprachigen Volksnamen an. Der Prozess
läuft im Hintergrund, ist jederzeit unterbrechbar und kann nach App-Neustart
weitermachen.

Das Kernziel ist eine gute UX: Das Deck soll möglichst schnell mindestens ein
Bild pro Species haben (→ „ready"), bevor weitere Enrichment-Stages
weiterlaufen.

---

## Pipeline

Die Enrichment-Pipeline besteht aus sechs sequenziellen Stages, die für jedes
Deck in dieser Reihenfolge ablaufen:

```
cover → nameResolution → base → inatPrimary → names → inatBackfill
```

| Stage | Was passiert |
|---|---|
| `cover` | Deck-Cover-Bild herunterladen und lokal speichern |
| `nameResolution` | Freitext-Eingabenamen (z. B. beim manuellen Deck-Erstellen) via iNat-API zu konkreten Species auflösen |
| `base` | Referenzbilder aus der Reference-DB (FishBase / SeaLifeBase) lokal runterladen |
| `inatPrimary` | Pro Species ein iNat-Foto holen; Species ohne Referenzbild werden priorisiert |
| `names` | Volksnamen pro Species **und** pro Taxonomie-Ebene (genus/family/order/class) via iNat-API |
| `inatBackfill` | Weitere iNat-Fotos bis `targetPhotoCount = 10` pro Species |

Das Deck gilt als **ready** sobald `hasAnyImage = true` im Job-Payload steht.
Das Flag wird gesetzt, sobald die erste Stage (`base` oder `inatPrimary`) für
mindestens eine Species ein Bild heruntergeladen hat. Ab diesem Punkt
übernehmen die Deck-Cards die Statusanzeige; der globale Banner verschwindet.

---

## Architektur-Komponenten

### `INatEnrichmentQueueService`
`lib/enrichment/service/inat_enrichment_queue_service.dart`

Der zentrale ChangeNotifier für Enrichment-State. Verantwortlich für:
- Jobs planen (`scheduleDeckEnrichment`)
- Foreground-Runner starten und am Leben halten
- App-Lifecycle-Ereignisse (resume/background) verarbeiten
- Netzwerk-Zustand überwachen und Runner steuern
- Status aus der DB ableiten und an die UI propagieren

Die public API ist bewusst klein: `scheduleDeckEnrichment`, `cancelDeckEnrichment`,
`deckInfo(deckId)`, `status`.

**Wichtig:** Der Service startet bei App-Start einen Foreground-Runner im
UI-Isolat. Auf Android hält ein Foreground-Service-Notification den Prozess
am Leben, wenn die App im Hintergrund ist. Workmanager ist bewusst deaktiviert —
er spawnt ein zweites Isolat, das mit dem UI-Isolat um den User-DB-Writer-Lock
konkurriert.

### `EnrichmentJobExecutor`
`lib/enrichment/service/enrichment_job_executor.dart`

Führt die eigentliche Arbeit aus. Verantwortlich für:
- Stage-Loop: `processUntilIdle` holt Jobs via `claimNextJob` und führt bis zu
  `maxStageRuns = 24` Stages pro Lauf aus
- Pro Stage: einen checkpointed Batch von Species verarbeiten
- Checkpoint-Batching: `_checkpointFlushSize = 5` abgeschlossene Species werden
  gepuffert, bevor in die DB geschrieben wird (reduziert DB-Writes und
  UI-Refreshes von N auf N/5)
- Fehler klassifizieren (`temporary` / `permanent`) und Jobs entsprechend
  in `retryScheduled` oder `failedPermanent` überführen
- Telemetrie / Diagnostics pro Stage und pro Run

### `EnrichmentService`
`lib/enrichment/service/enrichment_service.dart`

Führt die iNat-API-Calls und Cache-Writes durch. Enthält:
- `downloadBaseImagesForSpecies` — Stage `base`
- `fetchINatPhotosForSpecies` — Stage `inatPrimary`
- `backfillINatPhotosForSpecies` — Stage `inatBackfill`
- `fetchSpeciesCommonNamesForSpecies` — Stage `names`, Species-Level
- `fetchINatTaxonomyCommonNamesForEntityKeys` — Stage `names`, Taxonomie-Level
- `_batchResolveKnownTaxonIds` — liest taxon-IDs aus Reference-DB und Cache in
  zwei Queries, bevor der Species-Loop startet
- `_prefetchTaxonDetails` — cached Batch-Detail-Abruf via `GET /v2/taxa/{ids}`

**Wichtig:** `allowTier3Fallback` (Fallback auf Observation-Fotos aus der
Wildnis, ohne Qualitätsbewertung) ist nur in `inatBackfill` aktiv, nicht in
`inatPrimary`. Das hält die Primärfotos qualitativ hochwertig.

### `EnrichmentJobRepository`
`lib/enrichment/repository/enrichment_job_repository.dart`

Persistiert den Enrichment-State in der User-DB (`discere_user.db`,
Tabellen `enrichment_jobs` + `enrichment_job_stages`). Speichert:
- `EnrichmentJobPayload` als JSON-Blob (enthält `speciesIds`,
  `remainingSpeciesIdsByStage`, `remainingTaxonomyEntityKeysByStage`,
  `hasAnyImage`)
- Job-Status, Lease-Owner, Lease-Expiry, Retry-Count, `next_attempt_at`
- Stage-States (`pending`, `running`, `succeeded`, `failed`, `skipped`)
- Fortschritt (`progress_completed`, `progress_total`)

`_loadAllJobsBatched` lädt alle Jobs und alle Stage-States in je einer Query
und baut Records in-memory zusammen (kein N+1).

### `EnrichmentWorkRepository`
`lib/enrichment/repository/enrichment_work_repository.dart`

Koordiniert, welches Deck welche Species „besitzt". Da Species in mehreren Decks
vorkommen können, wird jeweils nur ein Deck für die Arbeit an einer Species
verantwortlich gemacht. Verhindert Doppelarbeit wenn zwei Decks dieselbe
Species haben.

### `EnrichmentForegroundServiceKeeper`
`lib/enrichment/service/enrichment_foreground_service_keeper.dart`

Android-only. Startet und stoppt eine `flutter_foreground_task`-Notification,
wenn die App im Hintergrund ist und aktive Arbeit vorliegt. Der mitgespawnte
`TaskHandler` ist ein No-op — die eigentliche Arbeit läuft weiterhin im
UI-Isolat. Notification-Text wird via `PlatformDispatcher.instance.locale`
zur Laufzeit lokalisiert (DE / EN).

### `HostCooldownTracker`
`lib/shared/service/host_cooldown_tracker.dart`

Zentrales Rate-Limit-Tracking. Wenn der iNat-API-Client einen 429 oder
Verbindungsfehler sieht, öffnet der Tracker einen Cooldown-Zeitraum. Der
`INatEnrichmentQueueService` hört auf `HostCooldownTracker`-Änderungen:
Wenn ein Cooldown endet, wird der Foreground-Runner neu gestartet, damit
`retryScheduled`-Jobs sofort wieder aufgenommen werden können.

---

## Schlüssel-Invariante: Terminal State Only

Die wichtigste Invariante der gesamten Pipeline:

> Eine Species darf für eine Stage nur dann als abgeschlossen markiert werden
> (`onSpeciesCompleted`), wenn sie einen **terminalen Zustand** erreicht hat.

Terminaler Zustand bedeutet:
1. Die Enrichment-Daten wurden erfolgreich geschrieben, **oder**
2. Ein explizites No-Result-Marker wurde geschrieben.

Konkret:
- `inat_photo_cache` enthält `__empty__` wenn iNat keine verwendbaren Fotos hat
- `runtime_common_names` enthält einen synthetischen No-Result-Eintrag wenn das
  Taxon aufgelöst wurde, aber keine Volksnamen existieren

Diese Invariante existiert, weil frühere Versionen Species nach dem Durchlaufen
des Loops sofort als fertig markiert haben. Das führte zu Silent-Success-Bugs:
Transiente Netzwerkfehler oder Taxonomie-Mismatches ließen eine Species ohne
iNat-Daten, während die Stage trotzdem als `succeeded` galt und der Banner
verschwand. Jetzt bleiben nicht-terminale Species in `remainingSpeciesIdsByStage`
und werden beim nächsten Run erneut versucht.

---

## Persistenz-Modell

```
discere_user.db
├── enrichment_jobs          — ein Eintrag pro Deck
│     status                 — queued | runningForeground | runningBackground |
│                              pausedBySystem | retryScheduled | cancelled |
│                              completed | failedTemporary | failedPermanent
│     payload_json           — EnrichmentJobPayload als JSON
│       speciesIds            — alle Species dieses Decks
│       remainingSpeciesIdsByStage  — Checkpoint pro Stage (was noch fehlt)
│       remainingTaxonomyEntityKeysByStage — Checkpoint für Taxonomie-Stage
│       hasAnyImage          — true sobald erstes Bild heruntergeladen
│     lease_owner / lease_expires_at — optimistisches Locking
│     next_attempt_at        — Retry-Zeitstempel bei retryScheduled
│
├── enrichment_job_stages    — ein Eintrag pro (deck_id, stage)
│     stage_state            — pending | running | succeeded | failed | skipped
│
├── inat_photo_cache         — gecachte iNat-Fotos pro species_id
│
├── external_identifier_cache — Laufzeit-aufgelöste taxon_ids (nicht im ETL)
│
└── runtime_common_names     — Laufzeit-geholte Volksnamen pro entity_key + lang
```

Die Reference-DB (`discere_reference.db`) enthält ETL-produzierte taxon-IDs in
`entity_external_ids`. Runtime-aufgelöste IDs gehen in
`external_identifier_cache`. Bei Lookups hat `entity_external_ids` Vorrang.

---

## Execution-Modell

```
App start
  └── INatEnrichmentQueueService.initialize()
        ├── _attachLifecycleObserver()      — AppLifecycle-Events hören
        ├── _networkSubscription            — Online/Offline-Events hören
        ├── _hostCooldownTracker.addListener — Cooldown-Ende hören
        └── _ensureForegroundRunner()
              └── _runForegroundJobs()      — im UI-Isolat
                    └── executor.processUntilIdle()
                          └── for up to 24 stages:
                                claimNextJob()         — DB-Lease setzen
                                _runStage(...)         — Arbeit ausführen
                                markStageSucceeded / markStageYielded / markStageRetryScheduled

App backgrounded (Android)
  └── _onBackgrounded()
        └── _syncForegroundServiceKeeper()
              └── keeper.startKeepingAlive()  — Notification starten

Cooldown ends
  └── _syncCooldownStatus()
        └── _ensureForegroundRunner()        — Runner neu starten

Network online
  └── _handleNetworkStatusChanged()
        └── _ensureForegroundRunner()
```

Der Foreground-Runner ist ein einfacher `Future<void>`, der null ist wenn er
nicht läuft. `_ensureForegroundRunner()` startet ihn nur, wenn er nicht bereits
läuft, kein Interactive-Hold aktiv ist und das Netz online ist.

---

## iNat-API-Nutzung

| Endpunkt | Verwendung |
|---|---|
| `GET /v2/taxa` | Taxon-Suche und Namensauflösung |
| `GET /v2/taxa/{id1,id2,...}` | Batch-Detail-Abruf (nested fields) |
| `GET /v2/observations` | Fotos aus Beobachtungen (POST + X-HTTP-Method-Override) |
| `GET www.inaturalist.org/taxon_names.json` | Volksnamen (Legacy-Endpunkt) |

Background-Parameter: `maxConcurrent = 1`, `requestSpacing = 1.1 s`.
iNaturalist-Bilder werden bewusst seriell geladen (`maxConcurrentINatImageDownloads = 1`),
da parallele Downloads kaum Durchsatzvorteil brachten, aber Gerätehitze und
Retry-Aufkommen erhöhten.

Der Legacy-Pfad für Volksnamen (`taxon_names.json`) bleibt bis ein verifizierter
V2-Endpunkt dieselbe Funktionalität liefert (Sprachzuordnung, mehrere Kandidaten
je Sprache, globales `position`-Ranking, ortsbezogene `place_taxon_names`-
Priorisierung).

---

## UX-State-Modell

| State | Wann | Banner-Verhalten |
|---|---|---|
| `idle` | Kein ausstehender Job | Kein Banner |
| `hasActiveWork` | `queued`, `running`, `pausedBySystem` | Banner sichtbar |
| `hasPendingWork` (aber kein `hasActiveWork`) | `retryScheduled`, `failedTemporary` | Banner sichtbar mit „Wird fortgesetzt" |
| `hasActiveHostCooldown` | Rate-Limit aktiv | Banner mit Cooldown-Hinweis |

**ready** (`isReady = hasAnyImage`): Das Deck hat mindestens ein Bild.
Deck-Card zeigt „Bereit, weitere Anreicherung läuft". Unterschied zu
**complete** (alle Stages durch).

`DeckEnrichmentInfo` (in `INatEnrichmentQueueService`) ist das DTO, das
die UI pro Deck konsumiert.

---

## Bekannte Einschränkungen

**Deck-zentrisches Modell:** Jeder Job gehört zu einem Deck. Species, die in
mehreren Decks vorkommen, werden pro Deck separat verarbeitet (außer wenn
`EnrichmentWorkRepository` die Ownership bereits zugewiesen hat). Bei großen
Imports mit überlappenden Decks entsteht dadurch redundante API-Arbeit.
→ Langfristig: import-weites Species-Work-Graph-Modell (beschrieben in
[Architecture Overview §4.8](../architecture-overview.md#48-target-design-import-wide-inaturalist-enrichment)).

**iOS-Background:** Auf iOS pausiert die Pipeline beim App-Suspend und wartet
auf den nächsten App-Start. BGTaskScheduler / BGProcessingTask wären ein
möglicher Weg, sind aber nicht implementiert.

---

## Offene Probleme (priorisiert)

### P0 — Direkt angehen

#### Permanent-Failure: Recovery nur über Edit-Deck erreichbar
Wenn eine Stage permanent fehlschlägt, landet der Job in `failedPermanent`.
Die Edit-Deck-Page zeigt in `_ManualINatEnrichmentSection` einen Fehlerstatus
und aktiviert den Trigger-Button (`canTrigger = true` weil `hasFailedAttempt`
den Button-Lock aufhebt). `scheduleDeckEnrichment` schreibt den Job via
`ConflictAlgorithm.replace` neu in `queued` — das ist ein funktionierender
Retry-Pfad.

**Das Problem:** Dieser Pfad ist nicht prominent genug. Der User sieht auf der
Deck-Liste oder Deck-Card einen Fehlerzustand, muss aber aktiv in Edit-Deck
navigieren um den Button zu finden. Ein direktes Retry-CTA auf der Deck-Card
oder im Deck-Header fehlt.

**Einfache Lösung:** Auf der Deck-Card oder im Deck-Header einen
„Erneut versuchen"-Button zeigen wenn `DeckEnrichmentInfo.hasFailedAttempt`.
Der Button ruft direkt `scheduleDeckEnrichment` auf — kein Cancel nötig, da
`scheduleDeckJob` mit `ConflictAlgorithm.replace` arbeitet.

---

### P1 — Wichtig, aber kein Blocker

#### Taxonomy-Volksnamen sind der Haupt-Engpass
`taxon_names.json` auf `www.inaturalist.org` ist der häufigste Kandidat für
429-Fehler und Timeouts. Die Taxonomie-Stage erzeugt pro Deck mehrere
Zusatzcalls für Genus/Family/Order/Class. Bei 100 Species + 50 Taxonomie-
Einheiten mit 1 Concurrency und 1.1 s Spacing wachsen allein die
Volksnamen-Calls auf über zwei Minuten.

**Keine bekannte einfache Lösung.** Langfristig: Genus/Family/Order/Class-
Volksnamen ins ETL verlagern (die Daten sind stabil-veränderlich und gute
Snapshot-Kandidaten). Passt zum geplanten Umbau auf regionale Sprachpräferenzen
in der Reference-DB. Bis dahin hilft nur, die Concurrency weiter zu reduzieren
oder Calls zwischen App-Sessions zu cachen (bereits teilweise durch
`external_identifier_cache` abgedeckt).

#### `next_attempt_at` wird nach Cooldown-Ende nicht zurückgesetzt
Wenn ein Job mit `next_attempt_at = +12 h` in `retryScheduled` steckt und
der `HostCooldownTracker` den Cooldown nach einer Minute beendet, ruft
`_syncCooldownStatus` zwar `_ensureForegroundRunner` auf — aber `claimNextJob`
überspringt Jobs, deren `next_attempt_at` noch in der Zukunft liegt. Der Job
bleibt also bis zu 12 h liegen, obwohl der Cooldown längst aufgelöst ist.

**Einfache Lösung:** In `_syncCooldownStatus` (oder in `claimNextJob` direkt)
`next_attempt_at` auf `null` setzen für alle `retryScheduled`-Jobs wenn
`cooldownJustCleared == true`.

#### iOS-Background-Strategie fehlt
Auf iOS friert die Pipeline beim App-Suspend ein. Kein explizites Resume,
kein BGTaskScheduler-Fallback. Der User muss die App manuell öffnen.

**Keine bekannte einfache Lösung.** Optionen:
- `BGProcessingTask` (iOS 13+): Erlaubt mehrstündige Hintergrundarbeit, aber
  nur wenn das Gerät aufgeladen ist und nicht benutzt wird. Nicht deterministisch.
- Push-getriggertes Resume: Erfordert Server-Infrastruktur.
- Bewusst als „iOS = Foreground only" dokumentieren und in der UI kommunizieren
  (z. B. Hinweis auf der Deck-Detail-Seite). Einfach, aber schlechtere UX.

---

### P2 — Mittelfristig sinnvoll

#### Taxonomy-Volksnamen ins ETL verlagern
Genus/Family/Order/Class-Volksnamen sind langsam-veränderlich und werden
aktuell bei jedem neuen Deck erneut live abgerufen. Sie sind ideale
ETL-Snapshot-Kandidaten.

**Kein direkter einfacher Weg** — erfordert Erweiterung des ETL-Schemas,
Regionalisierungs-Design (Sprachpräferenzen pro User), und Migrationsstrategie
für bestehende `runtime_common_names`-Einträge. Passt strukturell zum geplanten
Umbau auf regionale Sprachpräferenzen.

#### Import-weites Deduplication-Modell
Das aktuelle Modell ist deck-zentrisch: Jeder Job bearbeitet seine Species-Liste
unabhängig. Species, die in mehreren Decks vorkommen, erzeugen redundante
API-Calls. `EnrichmentWorkRepository` verhindert das für gleichzeitig laufende
Jobs, aber nicht über Deck-Import-Grenzen hinweg.

**Langfristiger Umbau** (kein einfacher Fix): Import-weites `speciesWork`-Modell
mit globalem `taxonResolveMemo`, separatem `taxonomyWork`-Graph und
Prioritätsscore. Details in
[Architecture Overview §4.8–4.9](../architecture-overview.md#48-target-design-import-wide-inaturalist-enrichment).

#### iNat-Open-Data für offline `taxon_id`-Mapping
Die `inaturalist-open-data`-Snapshots enthalten stabile `taxa`-Daten. Sie
könnten `entity_external_ids` im ETL anreichern und Live-Taxon-Resolves auf
echte Misses reduzieren.

**Kein bekannter einfacher Weg** — erfordert ETL-Integration des Open-Data-Repos
und Abgleich mit dem bestehenden `entity_external_ids`-Schema. Volksnamen und
kuratierte Fotos sind im Open-Data-Snapshot nicht gleichwertig abgedeckt
(kein Sprachranking, keine `place_taxon_names`-Priorisierung).
