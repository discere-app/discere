# iNaturalist-Enrichment — wie der Ablauf funktioniert

**Kategorie:** Architektur-Referenz (Ist-Zustand) · **Status:** Aktuell (Stand 2026-07-31)

Kurzreferenz für den aktuellen Enrichment-Ablauf nach dem Producer-Consumer-
Rewrite (löst das alte, sequenzielle 6-Stage-Job-Modell ab). Für die
ursprüngliche Problemanalyse siehe
[GitHub Issue #56](https://github.com/discere-app/discere/issues/56), für das
Target-Design, das dieser Rewrite umsetzt, siehe
[GitHub Issue #57](https://github.com/discere-app/discere/issues/57).

## Wozu

Nach Erstellen/Importieren eines Decks (oder Hinzufügen von Species zu einem
bestehenden Deck) reichert Discere jede Species im Hintergrund an:
Referenzbilder aus der ETL-Datenbank herunterladen, zusätzliche Fotos und
mehrsprachige Volksnamen von iNaturalist nachladen. Ziel: möglichst schnell
mindestens ein Bild pro Species, ohne die App zu blockieren.

## Warum Producer-Consumer statt einer Stage-Ladder

Das alte Modell führte pro Deck **einen Job mit sechs strikt sequenziellen
Stages** aus (`cover → nameResolution → base → inatPrimary → names →
inatBackfill`) — eine reine Prioritäts-Leiter, keine echte Datenabhängigkeit.
Das hatte drei konkrete Probleme:

1. `base` (Referenzbild-Download, unlimitiert, keine Rate-Limits) musste
   hinter `nameResolution` warten, obwohl es davon überhaupt nicht abhängt.
2. `nameResolution` war ein hartes Gate: eine Handvoll nicht auflösbarer
   Namen blockierte die **gesamte übrige Species-Liste** des Decks.
3. `inatPrimary` fragte für jede noch nicht iNat-gecachte Species ein Foto an
   — unabhängig davon, ob bereits ein funktionierendes Referenzbild vorlag.

Der Rewrite ersetzt die vier species-bezogenen Capabilities (`base`,
`inatPrimary`, `names`, `inatBackfill`) durch ein **Producer-Consumer-Modell**:
zwei unabhängig laufende Worker teilen sich eine persistierte
Prioritäts-Queue, sodass schnelle/günstige Arbeit (`base`) und
langsame/rate-limitierte Arbeit (iNat) sich nie gegenseitig blockieren, und
reaktive Folge-Arbeit pro Species entsteht, statt über Batch-weite Gates.
`cover` bleibt ein triviales Ein-Download-pro-Deck-Häppchen und läuft
weiterhin als eigener Mini-Job.

## Ablauf

```mermaid
flowchart TD
    A["Deck erstellt / importiert / Species hinzugefügt<br/>(ggf. mehrere Decks auf einmal)"] --> B["scheduleDeckEnrichment([DeckId, ...])<br/>(INatEnrichmentQueueService)"]
    B --> OWN["EnrichmentWorkRepository.assignSpeciesOwners():<br/>Species-Ownership-Dedup über alle aktiven Decks,<br/>OR't wants_inat_photos/wants_common_names additiv<br/>(nie ein Downgrade), seedt base (immer) +<br/>speciesCommonNames (nur bei Consent) als 'pending'"]
    OWN --> COVER["scheduleDeckJob(): 1 Cover-Mini-Job pro Deck<br/>(nur die cover-Stage, EnrichmentJobRepository)"]
    OWN --> UNRES["seedUnresolvedNames(): Freitext-Namen ohne<br/>FishBase/SLB-ID landen in enrichment_unresolved_names"]

    subgraph PASS ["Ein '_runForegroundJobs'-Durchlauf (Future.wait — läuft parallel)"]
        direction LR
        BW["BaseWorker.runUntilIdle()<br/>claimBaseWorkBatch (bis zu 25/Batch)<br/>bis zu 3 Species PARALLEL,<br/>kein Rate-Limit (nicht-iNat-Host)"]
        IW["INatWorker.runUntilIdle()<br/>claimNextINatWorkItem (1 Item)<br/>SERIELL, 1.1s Abstand —<br/>der einzige iNat-Consumer"]
        CJ["CoverJobRunner.runUntilIdle()<br/>claimNextJob (cover-Stage)"]
    end

    COVER --> PASS
    UNRES --> PASS

    BW -->|"kein Referenzbild vorhanden,<br/>oder Download nach 5 Versuchen aufgegeben"| SEED1["seedCapability(inatPrimary@10)<br/>seedCapability(inatBackfill@40)<br/>— nur falls wants_inat_photos"]
    BW -->|"Download erfolgreich"| SEED2["seedCapability(inatBackfill@40)<br/>— nur falls wants_inat_photos"]
    SEED1 --> IW
    SEED2 --> IW

    IW -->|"primäres iNat-Foto aufgelöst<br/>(done ODER noResult)"| SEED3["seedCapability(inatBackfill@40)<br/>+ seedTaxonomyWorkForSpecies()"]
    IW -->|"Name erfolgreich aufgelöst<br/>(nameResolution@50)"| STRAG["registerResolvedSpeciesForDeck():<br/>'Nachzügler-Runde', additiv,<br/>mit dem ursprünglich übermittelten Consent"]
    SEED3 --> IW
    STRAG --> IW

    PASS --> PROJ["EnrichmentWorkRepository.loadDeckProjection(deckId)<br/>aggregiert über enrichment_species_capability_state<br/>+ enrichment_taxonomy_work via deck-Membership"]
    PROJ --> STATE["computeDeckEnrichmentState():<br/>pending / loadingBase / loadingExtended /<br/>done / doneWithGaps / cooldown / paused / failed"]
    STATE --> UI["DeckEnrichmentHint (Deck-Karte),<br/>DeckSessionPresenter (Karten mit/ohne Bild)"]

    PASS -.->|"Review-Session aktiv?"| INT["enterInteractivePriorityMode():<br/>Foreground-Pass pausiert, nur die aktuell<br/>sichtbare Karte wird gezielt nachgeladen"]
```

Die drei Worker (`BaseWorker`, `INatWorker`, `CoverJobRunner`) laufen **im
selben `Future.wait`-Durchlauf**, also echt nebenläufig zueinander (nicht nur
verschachtelt wie früher eine (Job, Stage)-Kombination pro Executor-Tick).
Innerhalb von `BaseWorker` läuft zusätzlich echte Parallelität (`maxConcurrent
= 3`); `INatWorker` bleibt bewusst streng seriell, da es der einzige
Konsument des rate-limitierten iNat-Requestbudgets ist.

## Die zwei Worker im Detail

| Worker | Zieht aus | Capabilities | Nebenläufigkeit | Rate-Limit |
|---|---|---|---|---|
| `BaseWorker` | `claimBaseWorkBatch` (`enrichment_species_capability_state`, `capability = 'base'`) | `base` | bis zu 3 Species parallel, Batches à 25 | keiner (FishBase/SeaLifeBase, nicht iNat) |
| `INatWorker` | `claimNextINatWorkItem` (drei Quellen, niedrigster `priority_tier` gewinnt) | `inatPrimary` (10), `speciesCommonNames` (20), `taxonomyCommonNames` (30), `inatBackfill` (40), `nameResolution` (50) | streng seriell, 1 Item nach dem anderen | `1.1s` Abstand zwischen Claims |

`INatWorker` bündelt fünf Capabilities in **einer** Queue statt getrennter
Pfade — genau damit "ein rate-limitierter iNat-Konsument" eine echte Invariante
bleibt und nicht zwei unabhängige Pfade das Request-Budget gemeinsam
überziehen können. Die Namensauflösung (`nameResolution`, früher eine eigene,
ungedrosselte Stage) läuft deshalb jetzt an der niedrigsten Prioritätsstufe
in genau derselben Queue mit.

**Wichtige Vereinfachung:** `speciesCommonNames`/`taxonomyCommonNames` werden
immer als `'done'` markiert, sobald der Fetch terminal ist — es gibt keinen
Weg, von außen "echte Namen gefunden" von "bestätigt leer" zu unterscheiden
(`RuntimeCommonNameRepository` speichert den No-Result-Marker als ganz
normale Zeile in derselben Tabelle, die für "hat Namen" geprüft wird).
`inatBackfill` gate't die Deck-Bereitschaft nie (best-effort, "noch mehr
Fotos") — nur `base`/`inatPrimary` zählen für `imageStagesComplete`.

## Consent-Modell (additiv, nie ein Downgrade)

`includeINatPhotos`/`includeCommonNames` sind Parameter, die beim Schedulen
übergeben werden (keine persistente Deck-Einstellung). Sie werden **pro
Species** (nicht pro Deck) additiv verODERt in
`enrichment_species_work.wants_inat_photos`/`wants_common_names`:

- Eine Species, die einmal Consent von irgendeinem Deck bekommen hat, behält
  ihn — auch wenn ein anderes Deck, das dieselbe Species referenziert, ihn
  ablehnt (`assignSpeciesOwners`).
- `seedCapability` prüft `wants_inat_photos` selbst, bevor es `inatPrimary`/
  `inatBackfill` reaktiv anlegt — ein Species, die nur zu einem Deck ohne
  iNat-Consent gehört, bekommt dadurch **nie** ein iNat-Foto angefragt, egal
  was mit ihrem Referenzbild passiert.
- Ein Schedule-Aufruf für Deck B darf niemals stillschweigend Consent für ein
  anderes, gerade noch laufendes Deck A hochziehen, nur weil beide dieselbe
  Species teilen und A "der Einfachheit halber" mit übergeben wird (dedup,
  siehe unten) — dafür wird für alle nur mitgeschleppten Decks explizit
  `false` übergeben, statt das Feld auszulassen.

## Retry-/Resume-Strategie

Jede Capability-Zeile (`enrichment_species_capability_state`,
`enrichment_taxonomy_work`, `enrichment_unresolved_names`) durchläuft
denselben Zustandsautomaten — unabhängig davon, ob es eine Species-, eine
Taxonomie- oder eine Namensauflösungs-Zeile ist:

```mermaid
flowchart TD
    START(["seedCapability() /<br/>assignSpeciesOwners()<br/>(base immer, speciesCommonNames nur mit<br/>Consent, inatPrimary/inatBackfill nur mit<br/>Consent + reaktiv)"]) --> PENDING["pending"]

    PENDING -->|"claimBaseWorkBatch() /<br/>claimNextINatWorkItem()<br/>(nur falls noch eine<br/>deck_membership-Zeile existiert)"| RUNNING["running"]

    RUNNING -->|"Fetch erfolgreich,<br/>echtes Ergebnis geschrieben"| DONE(["done"])
    RUNNING -->|"Fetch erfolgreich,<br/>explizit bestätigt leer"| NORESULT(["noResult"])
    RUNNING -->|"fehlgeschlagen, classifyEnrichmentFailure()<br/>== temporary UND attempt_count < 5"| RETRY["retryScheduled"]
    RUNNING -->|"classifyEnrichmentFailure() == permanent<br/>(sofort, kein Retry-Budget verbrannt) ODER<br/>5. Versuch bei temporary auch fehlgeschlagen"| PERM(["permanentFailure"])

    RETRY -->|"next_attempt_at erreicht<br/>(Backoff: 15s/30s/1m/2m/4m)"| PENDING

    RUNNING -.->|"App/Prozess killt mid-claim —<br/>recoverInterruptedWork() beim nächsten<br/>App-Start (blanket reset, kein Lease nötig)"| PENDING

    PERM -.->|"BaseWorker: fällt auf<br/>inatPrimary/inatBackfill zurück<br/>(falls konsentiert)"| PENDING
```

Wichtige Details dazu:

- **Klassifizierung vor Retry-Entscheidung** (`classifyEnrichmentFailure`,
  geteilt mit `CoverJobRunner`): `TimeoutException`/`http.ClientException`/
  ein retrybarer `HttpDownloadException` gelten als `temporary` (volles
  5-Versuche-Backoff-Budget); alles andere — inklusive eines nicht-retrybaren
  `HttpDownloadException` (z. B. 404) — gilt als `permanent` und gibt sofort
  auf, statt ~7 Minuten Backoff für einen Fehler zu verbrennen, der ohnehin
  nie erfolgreich gewesen wäre.
- **Crash-Recovery ist ein blanket reset, kein Lease-System:** Anders als
  `EnrichmentJobRepository`'s Job-Leases (mehrere mögliche Runner-Instanzen)
  gibt es pro Prozess genau einen `BaseWorker`/`INatWorker`. Jede beim letzten
  Absturz `running` gebliebene Zeile wird beim nächsten App-Start blanket auf
  `pending` zurückgesetzt (`recoverInterruptedWork()`, aufgerufen in
  `INatEnrichmentQueueService._initialize()`).
- **Claims respektieren cross-deck Löschungen:** `claimBaseWorkBatch`/
  `claimNextINatWorkItem` claimen eine Species-Zeile nur, wenn noch
  mindestens eine `enrichment_species_deck_membership`-Zeile für sie
  existiert. Wurde das letzte Deck, das eine Species referenziert hat,
  gelöscht (`releaseDeck`), bleibt ihre `enrichment_species_capability_state`-
  Zeile zwar als permanenter Dedup-Cache liegen (siehe unten), wird aber nie
  wieder geclaimt — kein verschwendeter Download/iNat-Request für ein Deck,
  das nicht mehr existiert.
- **Reaktive Folge-Arbeit statt Batch-weiter Gates:** `BaseWorker` seedet bei
  Fehlschlag/fehlendem Referenzbild `inatPrimary`+`inatBackfill`; `INatWorker`
  seedet nach einer aufgelösten `inatPrimary` zusätzlich `inatBackfill` +
  ggf. Taxonomie-Arbeit; ein aufgelöster Name registriert die Species
  additiv nach ("Nachzügler-Runde", `registerResolvedSpeciesForDeck`). Jede
  dieser Folge-Seeds ist idempotent (`ConflictAlgorithm.ignore`) und
  respektiert dieselbe Consent-Prüfung wie oben.
- **Host-Cooldown ist rein informativ:** `HostCooldownTracker` (gespeist von
  `LoggingHttpClient`s HTTP-Fehlerprotokoll) gate't keine Requests der Worker
  selbst — die eigentliche Drosselung passiert ausschließlich über die
  Backoff-Schritte pro Capability-Zeile oben. Der Tracker steuert nur die
  `DeckEnrichmentState.cooldown`-Anzeige und ob die Android-Foreground-
  Service-Notification aktiv bleiben soll.
- **Foreground-Runner-Restart-Lücke (behoben):** `_ensureForegroundRunner()`
  markiert einen Restart-Wunsch, wenn es aufgerufen wird, während bereits ein
  `_runForegroundJobs()`-Durchlauf läuft — sonst könnte neu geschedulte
  Arbeit (z. B. ein zweiter `scheduleDeckEnrichment`-Aufruf kurz nach dem
  ersten) verloren gehen, bis irgendein unabhängiges Ereignis (App-Resume,
  Netzwerkwechsel) zufällig einen neuen Durchlauf anstößt.
- **Verklemmtes natives DB-Handle beim Neustart (abgemildert):**
  `main.dart` schließt bei `AppLifecycleState.detached` (Engine-Teardown,
  z. B. wenn Android die Activity killt, während der Foreground-Service den
  Prozess am Leben hält) beide Datenbanken via `DatabaseHelper.close()` —
  sqflites natives Handle ist prozessweit pro Pfad, ein späteres
  `openDatabase()` auf denselben Pfad würde sonst unbegrenzt hängen (der
  konkrete Verdacht bei einem gemeldeten "hängt im Splashscreen fest" nach
  diesem Rewrite: die beiden Worker halten die User-DB jetzt deutlich öfter
  beschäftigt als das alte, seltener laufende Job-Modell). Ein
  `integration_test` (`enrichment_shutdown_test.dart`) mit `close()` unter
  echter Worker-Last auf echtem Gerät konnte diesen konkreten Mechanismus
  nicht reproduzieren — die DatabaseException-Toleranz der Worker fängt das
  sauber ab, `close()` selbst hängt dabei nicht. Der eigentliche, bestätigte
  Bug lag eine Ebene tiefer: `DatabaseHelper._openReferenceDb`/`_openUserDb`
  hatten **gar kein** Timeout auf dem nativen Open-Call — ein verklemmtes
  Handle (aus welcher Ursache auch immer) hätte den gecachten
  Initialisierungs-`Future` für immer offengehalten, sodass jeder spätere
  Zugriff (ein Retry-Tap auf dem Bootstrap-Error-Screen, ein späterer
  Repository-Call) auf demselben toten Future wartet, ohne je eine Chance auf
  einen frischen Open-Versuch. Jetzt bricht der native Open nach 8s mit
  einer Exception ab, wodurch der schon vorhandene `catchError`-Reset auf
  `_referenceInitialization`/`_userInitialization` tatsächlich greift.
  `_refreshStateNow()` fängt dafür jetzt auch `TimeoutException` (nicht nur
  `DatabaseException`) ab, damit ein Timeout beim allerersten DB-Zugriff
  `_initialize()` nicht abbricht, bevor Lifecycle-Observer und
  Foreground-Runner überhaupt aufgesetzt sind.
- **Eingefrorene Deck-Projection nach Prune der letzten Species (behoben):**
  `pruneSpeciesMembershipIfFullyTerminal` löscht die
  `enrichment_species_deck_membership`-Zeile(n) einer Species, sobald wirklich
  alles (inkl. Taxonomie) terminal ist — damit verschwindet aber auch der
  einzige Weg, mit dem `loadDeckIdsUpdatedSince`'s Delta-Query per Join
  herausfinden kann, zu welchem Deck diese Species gehörte. War die geprunte
  Species die letzte des Decks, kann `INatEnrichmentQueueService` dieses Deck
  danach nie wieder als "geändert" erkennen — seine gecachte
  `DeckEnrichmentProjection` friert für immer im letzten beobachteten
  Zwischenstand ein (z. B. dauerhaft `loadingExtended` statt korrekt
  `done`/`hidden`). Bei seltenem Polling (vor der Live-Fortschritts-Änderung
  oben) fiel das kaum auf, weil der erste jemals geladene Snapshot meist
  schon nach dem Prune lag; mit dem granularen `onProgress`-Refresh wird ein
  Zwischenstand zuverlässig *vor* dem Prune eingelesen und friert dann sichtbar
  ein. Fix: `pruneSpeciesMembershipIfFullyTerminal` gibt jetzt die betroffenen
  Deck-IDs zurück (aus der Membership-Tabelle gelesen, bevor sie gelöscht
  wird); `INatWorker` reicht sie über einen neuen `onDecksNeedForcedReload`-
  Callback an `INatEnrichmentQueueService` weiter, die sie unabhängig vom
  Delta-Zeitstempel einmalig neu lädt.

## Mehrere Decks gleichzeitig / Cross-Deck-Dedup

`scheduleDeckEnrichment()` nimmt weiterhin eine **Liste** von Deck-IDs
entgegen. Die Dedup-Logik ist import-weit, nicht mehr batch-lokal:

**1. Species-Ownership** (`EnrichmentWorkRepository.assignSpeciesOwners`,
Tabelle `enrichment_species_work`) — verhindert, dass dieselbe Species von
mehreren gleichzeitig aktiven Decks unabhängig voneinander bei iNat
angefragt wird:
- Jede Species bekommt genau ein `owner_deck_id` (Tie-Break-Bookkeeping,
  keine exklusive Kontrolle) — **jedes** referenzierende Deck bekommt aber
  eine Zeile in `enrichment_species_deck_membership`, und die
  `enrichment_species_capability_state`-Zeilen sind ohnehin global pro
  Species, nicht pro Deck. Ein Deck muss also nicht "Owner" sein, um von
  bereits fertiger Arbeit für eine geteilte Species zu profitieren.
- Einmal vergebene Ownership bleibt stabil, solange der Owner noch unter den
  beteiligten Decks ist. Bereits aktive Decks werden bei einem neuen
  `scheduleDeckEnrichment`-Aufruf mit niedrigerer Priorität einbezogen — nur
  um ihre Species-Zuordnung zu schützen, ohne ihnen selbst neuen Consent zu
  gewähren (siehe Consent-Modell oben).
- `enrichment_species_capability_state` ist der **permanente** Dedup-Cache:
  wird eine Species aus jedem Deck entfernt (`releaseDeck`), bleibt diese
  Zeile bestehen — kommt die Species später in einem neuen Deck wieder vor,
  muss nichts doppelt geholt werden.
- Löscht das Deck, das gerade `owner_deck_id` einer geteilten Species ist,
  wird die Ownership auf ein verbleibendes Deck übertragen statt die
  Species-Zeile (und damit die Arbeit anderer Decks) einfach zu verwerfen.

**2. Taxonomie-Dedup** (`assignTaxonomyOwners`/`enrichment_taxonomy_work`,
Schlüssel `rank + taxon_id` bzw. `rank + scientific_name`) — Genus-/Familien-/
Ordnungs-/Klassen-Volksnamen werden einmal pro Taxon geholt, nicht einmal pro
Species darin, unabhängig davon, wie viele Decks/Species darauf verweisen.

## Runtime-Modell

- **Läuft komplett in der UI-Isolate**, kein separater Background-Isolate.
  `lib/app/background/inat_background_task.dart` existiert nur noch als
  No-Op-Callback für Workmanager-Wakeups von alten App-Versionen.
- Damit der Android-Prozess bei Bildschirm aus nicht vom OS beendet wird,
  hält `EnrichmentForegroundServiceKeeper` einen echten Android-Foreground-
  Service mit Notification am Laufen, solange Arbeit offen ist.
- Getriggert wird `_runForegroundJobs()` bei `scheduleDeckEnrichment()`, bei
  App-Start (`initialize()`) und bei jedem Wiedereintritt in den Vordergrund
  (`AppLifecycleState.resumed`) sowie bei Netzwerk-Wiederverbindung. Läuft
  nur, wenn online (`NetworkAvailability`).
- **Pausiert während einer aktiven Lern-Session:** `DeckPage` ruft beim
  Öffnen `enterInteractivePriorityMode()` auf — die drei Worker halten an,
  damit sie nicht mit dem gezielten Nachladen der gerade sichtbaren Karte
  um Bandbreite/DB-Zugriff konkurrieren.
- **Live-Fortschritt statt Sprung am Pass-Ende:** `BaseWorker`/`INatWorker`
  feuern einen `onProgress`-Callback nach *jeder einzelnen* verarbeiteten
  Species/Item, nicht erst wenn der komplette `_runForegroundJobs()`-Durchlauf
  fertig ist — sonst hätte die UI bei einem großen Batch (z. B. 20 Arten ×
  ~1.1s `INatWorker`-Taktung) minutenlang keinerlei sichtbare Bewegung.
  `INatEnrichmentQueueService._notifyProgress()` ruft dafür einfach
  `_refreshState()` auf — kein neuer Event-Bus nötig, da dieser Delta-Refresh
  bereits selbst-koaleszierend ist (mehrere Aufrufe kollabieren zu einem
  Durchlauf, `notifyListeners()` feuert nur bei echter Änderung). Die
  zusätzlichen Refresh-Aufrufe machten eine bestehende Dispose-Race
  wahrscheinlicher (in CI beobachtet, lokal nicht reproduzierbar): `dispose()`
  prüft `_disposed` zwar am Funktionseinstieg, aber `_refreshStateNow()`/
  `_syncCooldownStatus()` erreichen `notifyListeners()` erst nach mehreren
  `await`-Punkten (Delta-Queries, Projection-Reload, Foreground-Service-/
  Notification-Sync) — disposed genau in einer dieser Lücken löste
  `ChangeNotifier`s Debug-Assert aus ("used after being disposed"). Fix:
  `_disposed` wird jetzt unmittelbar vor jedem `notifyListeners()`-Aufruf
  erneut geprüft, nicht nur beim Eintritt.

## Wichtige Komponenten

| Komponente | Pfad | Verantwortung |
|---|---|---|
| `INatEnrichmentQueueService` | `queue/service/` | Einstiegspunkt (`scheduleDeckEnrichment`), Lifecycle-/Foreground-Steuerung, leitet `DeckEnrichmentState`/`DeckEnrichmentInfo` für die UI ab |
| `BaseWorker` | `pipeline/service/` | Zieht `base`-Arbeit, echte Parallelität, kein Rate-Limit |
| `INatWorker` | `pipeline/service/` | Einziger rate-limitierter iNat-Konsument über fünf Capabilities inkl. Namensauflösung |
| `CoverJobRunner` | `queue/service/` | Führt den verbleibenden Cover-Mini-Job aus (Lease/Retry, unverändert gegenüber dem alten Executor) |
| `EnrichmentJobRepository` | `queue/repository/` | Speichert nur noch die `cover`-Job-Zeilen (Lease, Retry, Payload) |
| `EnrichmentWorkRepository` | `pipeline/repository/` | Die eigentliche Queue: `enrichment_species_work`, `enrichment_species_capability_state`, `enrichment_taxonomy_work`, `enrichment_species_deck_membership`, `enrichment_unresolved_names` |
| `BaseImageEnrichmentService` / `INatPhotoEnrichmentService` / `SpeciesCommonNameEnrichmentService` / `TaxonomyCommonNameEnrichmentService` | `pipeline/service/` | Die eigentlichen Fetches (unverändert gegenüber der alten `EnrichmentService`-Aufteilung, nur jetzt von den Workern statt vom Executor mit Singleton-Sets aufgerufen) |
| `INatNameResolutionService` | `pipeline/service/` | Löst Freitext-Namen gegen iNat auf (`ScientificNameResolutionPort`) |
| `EnrichmentForegroundServiceKeeper` | `queue/service/` | Android-Foreground-Service-Notification, solange Arbeit offen ist |
| `HostCooldownTracker` | `shared/service/` | Rein informativ: UI-Cooldown-Anzeige + Keepalive-Signal, gate't keine Requests |

## Wo die UI das liest

- `DeckEnrichmentHint` (Deck-Karte) zeigt Status-Icon + Text aus
  `DeckEnrichmentInfo`/`DeckEnrichmentState` (`pending`, `loadingBase`,
  `loadingExtended`, `done`, `doneWithGaps`, `cooldown`, `paused`, `failed`).
  Ein Fortschritts-Prozentsatz (`progressCompleted`/`progressTotal` aus
  `deriveDisplayedProgress`, gerundet) wird bewusst erst ab `loadingExtended`
  angezeigt — also erst sobald das Deck tatsächlich lernbar ist
  (`imageStagesComplete`, ein Bild-Ergebnis pro Species). Im `loadingBase`-
  Zustand (Deck noch nicht lernbar) gibt es nur den reinen Statustext, keine
  Zahl — eine Prozentangabe hätte sonst "80%" wie "80% lernbereit" lesen
  lassen, obwohl noch gar nichts davon stimmt. `progressTotal` ist dabei kein
  reiner Artenzähler, sondern eine Summe über mehrere Capability-Zähler
  (Basisbild pro Species + Common-Names-Consent-Species + Backfill-Species +
  Taxonomie-Einträge je Genus/Familie/… + optional 1 für den Cover-Job) —
  ein Deck mit 10 Arten kann je nach Consent/Taxonomie-Lage einen `total`
  deutlich über 10 haben.
- `DeckSessionPresenter.filterReviewableCards` entscheidet pro Flashcard: ist
  `DeckEnrichmentProjection.imageStagesComplete` (= `base`+`inatPrimary` für
  alle Species terminal) noch `false`, werden fällige Karten ohne lokales
  Bild versteckt; ist es `true`, werden alle fälligen Karten gezeigt, auch
  ohne Bild.
- **Bekannter, akzeptierter Trade-off:** `DeckEnrichmentInfo.lastCompletedAt`/
  `lastAttemptedAt` nutzt für Decks ohne eigenen Cover-Job (kein Cover-URL
  beim Import) einen nur session-scoped In-Memory-Zeitstempel, da
  Species-/Taxonomie-Arbeit keine einzelne, deck-weite persistente
  Zeitstempel-Spalte mehr hat — nach einem App-Neustart zeigt so ein Deck
  "zuletzt abgeschlossen" ggf. nicht mehr an, auch wenn es in einer früheren
  Session fertig wurde. Ein Deck mit Cover-Job ist davon nicht betroffen.
- **Fehlt aktuell:** eine Deck-weite, persistente Aussage "für N Species
  wurde kein Foto gefunden" — dazu mehr in
  [GitHub Issue #53](https://github.com/discere-app/discere/issues/53).
