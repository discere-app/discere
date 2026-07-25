# iNaturalist Enrichment — Architektur & offene Probleme

**Kategorie:** Analyse (Architektur-Referenz) + Improvement-Punkte · **Status:** Aktuell (Stand 2026-07-23), aktiver Referenz-Doc

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

### P1 — Bild-Enrichment terminiert nicht bei dauerhaft fehlschlagenden Downloads (`base`/`inatPrimary`) — **umgesetzt**
**Priorität:** Hoch (kann Deck komplett unlernbar machen, kein User-Recovery-Pfad)
**Komplexität:** Mittel
**Kurzbeschreibung:** Anders als die Volksnamen- und iNat-Sekundär-Stage
(No-Result-Marker `__empty__` im iNat-Photo-Cache) hatten die Bild-Stages
`base` und `inatPrimary` keinen expliziten No-Result-Marker für dauerhaft
fehlschlagende Downloads. `downloadBaseImagesForSpecies`/
`fetchINatPhotosForSpecies` fangen jeden Fehler pro Species ab
(`enrichment_service.dart:137-139, 274-275`) und rufen `onSpeciesCompleted`
bewusst nur bei tatsächlich heruntergeladenem Bild auf — Design-Absicht laut
Kommentar in `_runSpeciesStageWithCheckpoint`
(`enrichment_job_executor.dart:665-683`): kein Auto-Complete nur weil die
Species „berührt" wurde, um False-Success zu vermeiden. Für eine Species mit
dauerhaft kaputter/nicht erreichbarer Bild-URL gab es dadurch aber gar
keinen Weg mehr in einen Terminal-Zustand: `everySpeciesHasImage`
(`enrichment_job.dart:220-226`) verlangt `succeeded` oder `skipped` für jede
Species in beiden Stages, `skipped` wird aber nur bei kompletter
Stage-Deaktivierung gesetzt, nie pro Species. Da der Fehler nirgends geworfen
wurde, griff auch die reguläre Retry-Exhaustion (`classifyEnrichmentFailure`
/ `markStageFailedPermanent`, `enrichment_job_executor.dart:246-259`) nicht —
die Species blieb für immer „remaining".
**Auswirkung:** `DeckSessionPresenter.filterReviewableCards`
(`deck_session_presenter.dart:52-58`) blendet alle Karten ohne lokales Bild
aus, bis `imageStagesComplete` true ist. Enthielt ein Deck auch nur eine
Species mit dauerhaft fehlschlagendem Bild, wurde `imageStagesComplete` fürs
ganze Deck nie wahr — im Extremfall blieb die Lernsession dauerhaft auf dem
„Bilder werden heruntergeladen"-Spinner stehen (`deck_page.dart`,
`_isWaitingForImages`), ohne dass gelernt werden konnte. Kein Recovery: der
bestehende Retry-CTA (`_EnrichmentHint` bei `DeckEnrichmentState.failed`,
siehe `OVERVIEW.md` P0) griff nicht, weil der Job nie in `failed` landete.
Konkret beobachtet als Ursache für einen fehlschlagenden Integrationstest
(`manual_card_activation_test.dart`) unter der absichtlich
netzwerk-blockierenden Testkonfiguration; im echten Betrieb realistischer bei
dauerhaft toten Bild-URLs oder lang anhaltendem Host-Ausfall statt
kompletter Offline-Nutzung.
**Umsetzung:** Statt eines stage-spezifischen No-Result-Markers wurde die
Lösung eine Ebene tiefer, am gemeinsamen Checkpoint-Mechanismus
`_runSpeciesStageWithCheckpoint`, angesetzt — der Punkt, den alle vier
species-checkpointed Stages (`base`, `inatPrimary`, `names`,
`inatBackfill`) durchlaufen. `EnrichmentJobPayload` trägt jetzt
`speciesStageAttemptCounts` (Stage → Species-ID → Versuchszähler),
persistiert im ohnehin checkpointeten Payload. Nach jedem Stage-Run wird für
jede Species, die dieser Run tatsächlich angefasst, aber nicht terminal
abgeschlossen hat, der Zähler erhöht; nach `_maxSpeciesStageAttempts` (= 5,
analog zu `_maxTemporaryRetries` auf Job-Ebene) wird die Species zwangsweise
über denselben `onSpeciesCompleted`-Callback terminal gesetzt — genau wie ein
echter No-Result-Marker propagiert das via `EnrichmentWorkRepository
.markSpeciesStageCompleted` auch deck-übergreifend, andere Decks mit
derselben Species probieren die tote URL also nicht erneut. Der Zähler wird
bei jedem echten Abschluss (Erfolg oder Give-up) wieder aus dem Payload
entfernt. Fix in `lib/enrichment/model/enrichment_job.dart` und
`lib/enrichment/service/enrichment_job_executor.dart`; Tests in
`test/enrichment/service/enrichment_job_executor_test.dart` (neue
Give-up-Tests für `base`) und `inat_enrichment_queue_service_test.dart`
(bestehender Test, der das alte „bleibt für immer pending"-Verhalten als
Soll-Zustand fixierte, wurde auf das neue Konvergenz-Verhalten umgestellt).

### P1 — Taxonomy-Volksnamen als Haupt-Engpass
**Priorität:** Mittel · **Komplexität:** Hoch (keine einfache Lösung bekannt)
**Kurzbeschreibung:** `taxon_names.json` (Legacy-Endpunkt) ist häufigster
Kandidat für 429/Timeout. Bei 100 Species + 50 Taxonomie-Einheiten mit
`maxConcurrent=1`/1.1s Spacing wachsen die Volksnamen-Calls auf über zwei
Minuten.
**Auswirkung:** Verlängert primär die Zeit bis Volksnamen vollständig
vorliegen, blockiert aber nicht die Bild-Stages (laufen vorher) — spürbar als
lange „unvollständige Übersetzung"-Phase, kein Blocker fürs Lernen selbst.
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
**Auswirkung:** Nutzer sieht ggf. unnötig lange fehlende Bilder/Namen für das
betroffene Deck, obwohl Netzwerk/Host längst wieder erreichbar sind — bis zu
12h Verzögerung ohne technischen Grund.
**Lösungsidee:** In `_syncCooldownStatus` (oder direkt in `claimNextJob`)
`next_attempt_at` auf `null` setzen für alle `retryScheduled`-Jobs, wenn
`cooldownJustCleared == true`.
**Probleme:** Keine bekannten — klar lokalisierter Fix.

### P1 — iOS-Background-Strategie fehlt
**Priorität:** Mittel · **Komplexität:** Hoch (keine einfache Lösung bekannt)
**Kurzbeschreibung:** Auf iOS friert die Pipeline beim App-Suspend ein, kein
Resume, kein BGTaskScheduler-Fallback.
**Auswirkung:** Enrichment läuft auf iOS effektiv nur, während die App aktiv
im Vordergrund ist — Nutzer muss die App offen halten bzw. wieder aktivieren,
damit Bilder/Namen weiter nachgeladen werden.
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

### P3 — Ungenutzte/zusätzliche Felder in bereits genutzten iNat-Endpunkten
**Priorität:** Niedrig · **Komplexität:** Niedrig–Mittel je Punkt
**Kurzbeschreibung:** Bei einer Durchsicht von `INaturalistService` (2026-07-19)
aufgefallen — Felder, die entweder schon abgerufen aber verworfen werden, oder
mit demselben Call zusätzlich verfügbar wären:
- `wikipedia_url` — **umgesetzt** (dieser Task): wird beim ohnehin schon
  gefetchten Taxon-Detail (`_taxonDetailFieldsExpanded`) mitgelesen und via
  `ExternalIdCacheRepository` (Provider `'wikipedia'`) persistiert, kein
  neuer Table/Call nötig. Angezeigt als Link-Chip in
  `SpeciesExternalLinks` (`catalog/species_detail/widgets/`).
- `wikipedia_summary` — wird im selben Response mitgeliefert, aber bewusst
  **nicht** gespeichert. Ohne `locale`-Query-Param liefert iNat nur Englisch;
  mit `?locale=de` gibt es keinen Fallback (leer statt Englisch, wenn keine
  kuratierte Übersetzung existiert — verifiziert per Live-Call). Plan: Summary
  separat über die Wikipedia-API selbst nachladen, mit dem passenden
  App-Locale, sobald `wikipedia_url` in der DB steht.
- `default_photo_url`/`default_photo_medium_url`/`default_photo_license_code`
  in `searchTaxa()` (Namens-/Taxonomie-Auflösung) — werden geparst, aber von
  keinem der beiden Aufrufer (`inat_reference_resolver.dart`,
  `inat_name_resolution_service.dart`) gelesen. Totes Feld, kein
  Handlungsbedarf, nur zur Kenntnis.
- `iconic_taxon_name` in `searchTaxa()` — gleiches Bild, ungenutzt.
- `observations_count` — aktuell nicht angefragt, aber ein normales
  Top-Level-Feld auf dem Taxon-Objekt (kein Zusatz-Call). Könnte (a) erklären/
  vorhersagen, warum manche Species nie ein Foto bekommen (sehr wenige
  Beobachtungen), oder (b) den Enrichment-Job solche Species schneller als
  „kein Bild verfügbar" terminal markieren statt endlos zu retryen. Bisher nur
  eine Idee, keine konkrete Lösungsidee ausgearbeitet.
- `conservation_status`, `establishment_means` (native/introduced/endemic
  pro Ort via `preferred_place_id`), `extinct` — alle ohne Zusatz-Call
  abrufbar, aber vermutlich redundant zur bestehenden Fishbase/Sealifebase-
  Regionslogik aus der ETL-Pipeline (siehe Endemiten-/Kontinent-Features).
  Nur relevant, falls sich dort nachweislich Lücken zeigen.
**Probleme:** Keine der Positionen ist dringend — reine
Gelegenheits-Findings, kein Bug.

## Bekannte strukturelle Einschränkung (kein einzelner Task)

Deck-zentrisches Modell + Terminal-State-Invariante (Species gilt erst als
fertig, wenn Enrichment-Daten geschrieben oder ein expliziter
No-Result-Marker gesetzt wurde) sind bewusste Architekturentscheidungen, kein
offener Bug. Verbleibende Race-Lücke bei gleichzeitigem Batch-Zugriff zweier
Executors auf dieselbe Species ist praktisch sehr unwahrscheinlich
(`maxConcurrent=1`, 1.1s Spacing) und führt zu keiner Datenkorruption
(Caches machen den zweiten Write zum No-Op).

Diese Invariante war ursprünglich nur so gut wie ihre No-Result-Marker: nur
die Volksnamen-Stage und die iNat-Sekundär-Stage hatten einen, die
Bild-Stages `base`/`inatPrimary` nicht — dort war „nie fertig" statt
„Datenkorruption" das tatsächliche Risiko. Seit dem Attempt-Cap in
`_runSpeciesStageWithCheckpoint` (siehe P1 „Bild-Enrichment terminiert nicht
bei dauerhaft fehlschlagenden Downloads" oben, **umgesetzt**) gilt die
Terminal-State-Invarianz für alle vier species-checkpointed Stages
gleichermaßen: entweder echter Erfolg, ein expliziter No-Result-Marker, oder
— neu — Give-up nach `_maxSpeciesStageAttempts` erfolglosen Versuchen.
