# iNaturalist Enrichment Strategy

Stand: 2026-05-04

## Pipeline

Nach `Deck importieren` oder `Deck erstellen` laeuft eine persistente,
resumebare Anreicherung in sechs Stages:

1. `cover` — Deck-Cover-Bild herunterladen
2. `nameResolution` — unaufgeloeste Eingabenamen ueber iNat zu Species aufloesen
3. `base` — Reference-DB-Bilder ausschreiben (FishBase / SeaLifeBase)
4. `inatPrimary` — iNat-Foto primaerer Pass (ein Foto pro Species)
5. `names` — Common Names pro Species + pro `genus/family/order/class`
6. `inatBackfill` — restliche Fotos bis `targetPhotoCount`

Die ersten drei Stages bilden den **Quick Pass**: sobald diese durch sind ist
das Deck fachlich nutzbar, auch wenn die iNat-Stages noch laufen.

Execution laueft ausschliesslich im UI-Isolat (Foreground-Runner). Auf Android
haelt eine Foreground-Service-Notification den Prozess am Leben, wenn die App
im Hintergrund ist. Workmanager ist bewusst deaktiviert — er hat mit dem
UI-Isolat um den User-DB-Writer-Lock konkurriert.

## API-Stand

| Endpunkt | Status |
|---|---|
| `GET /v2/taxa` — Resolve, Suche | V2, in Nutzung |
| `GET /v2/taxa/{id1,id2,...}` — Batch-Detail, nested fields | V2, in Nutzung |
| `GET /v2/observations` — Fotos aus Beobachtungen | V2, in Nutzung |
| `GET /taxon_names.json` (www.inaturalist.org) — Common Names | Legacy, kein V2-Ersatz bekannt |

Der Legacy-Pfad fuer Common Names bleibt bis ein verifizierter V2-Endpunkt
dieselbe Funktionalitaet liefert (Sprachzuordnung, mehrere Kandidaten je
Sprache, globales `position`-Ranking, ortsbezogene `place_taxon_names`-
Priorisierung).

## Offene Probleme

### Performance

**Tier-3-Observation-Fallback im inatPrimary-Hot-Path.** Wenn nach Curated- und
Research-Quality-Pass die Foto-Zahl noch unter `maxPhotos` liegt, faellt die
Pipeline in einen dritten Call ohne `quality_grade` zurueck — pro Species und
pro `inatPrimary`-Lauf. Verdoppelt im Worst Case die Observation-Calls.

**Resolve-Plan wird nicht vorziehen.** Die taxon-ID-Aufloesung passiert
sequentiell im Stage-Loop fuer jede Species, die keinen Eintrag in Reference-DB
oder User-Cache hat. Auf zwei iNat-Stages verteilt bedeutet das potenziell
doppelter Resolve-Aufwand.

**Common Names sind der Haupt-Engpass.** `taxon_names.json` auf dem Legacy-Host
ist der haeufigste Kandidat fuer `429` und Timeouts. Die Taxonomy-Stage
(genus/family/order/class) erzeugt bei jedem neuen Deck mehrere zusaetzliche
Calls fuer Taxa, die ausserhalb des ETL-Snapshots liegen. Mit 1 Concurrency und
1.1 s Spacing wachsen 100 Species + 50 Taxonomy-Entitaeten leicht ueber zwei
Minuten reine Common-Name-Zeit.

**Checkpoint schreibt pro Terminal-Outcome.** Pro Species-Done wird der volle
Payload als JSON neu serialisiert und in die User-DB geschrieben. Bei grossen
Decks konkurriert das mit Deck-Listing und Card-Reviews.

**`claimNextJob` ist N+1.** Pro Stage-Wechsel werden alle Jobs geladen, dann
pro Deck erneut die Stage-Tabelle abgefragt.

**Backoff resettet nicht bei Cooldown-Ende.** Ein Job, der mit `next_attempt_at
= +12 h` in `retryScheduled` steckt, bleibt da haengen, auch wenn der
HostCooldownTracker den Cooldown nach einer Minute schliesst.

### UX

**Banner-Fortschritt ist missverstaendlich.** `Phase X (12/100)` suggeriert „12
von 100 fertig", ist aber `12 von 100` in einer von vier Phasen.

**Quick-Pass-Ready wird nicht kommuniziert.** Das Deck ist nach der
base-Stage nutzbar, aber der Banner zeigt weiter „laeuft".

**Banner verschwindet fuer `retryScheduled`-Only-Zustaende.** Decks, die
automatisch nachts nochmals probieren, gelten nicht als „aktiv" — der Banner
fehlt, User denkt der Prozess ist abgeschlossen.

**Permanent-Failures haben kein Recovery-CTA.** Es gibt keinen prominenten
„N Arten konnten nicht geladen werden — erneut versuchen"-Einsprungpunkt.

**Foreground-Service-Notification ist hardcoded deutsch.**

**iOS-Background-Pfad fehlt.** Auf iOS pausiert die Pipeline beim Suspend und
wartet auf den naechsten App-Start.

## Maßnahmen

### P0

- **Tier-3-Fallback verschieben:** aus `inatPrimary` rausnehmen, ausschliesslich
  in `inatBackfill` triggern (oder hinter eine Min-Foto-Schwelle).
- **Resolve-Plan vorziehen:** vor `inatPrimary` und `names` einmal alle
  einzigartigen `(rank, scientificName)`-Paare sammeln, Reference-DB +
  User-Cache auslesen, nur echte Misses live aufloesen, Ergebnis sofort
  persistieren — inklusive Synonym-Mapping.
- **Checkpoint batchen:** erst alle N Terminal-Outcomes (5-10) oder
  zeitbasiert schreiben; letzter Outcome einer Stage bleibt atomar.
- **Backoff-Reset bei Cooldown-Ende:** wenn HostCooldownTracker einen
  Cooldown schliesst, alle `retryScheduled`-Jobs fuer diesen Host auf
  `next_attempt_at = jetzt + kleines Jitter` ziehen.
- **Banner fuer `retryScheduled`** sichtbar lassen: „Wird automatisch
  fortgesetzt um …" anzeigen.

### P1

- **N+1 in `claimNextJob`** durch JOIN ersetzen.
- **Quick-Pass-Ready kommunizieren:** „Deck einsatzbereit, weitere Daten
  laden im Hintergrund" auf Banner und Deck-Card ausspielen.
- **Permanent-Failure-Recovery-Flow:** Deck-Detail zeigt betroffene Arten
  plus Retry-Button.
- **Foreground-Service-Notification lokalisieren.**
- **Observation-Calls auf nested fields umstellen** (`POST + X-HTTP-Method-Override:
  GET`) — analog zu taxa-Endpoint.

### P2

- **Taxonomy-Common-Names ins ETL verlagern.** Genus/Family/Order/Class sind
  langsam-veraenderlich — ideale Snapshot-Kandidaten. Passt zum geplanten
  Umbau auf regionale Sprachpraeferenzen in der Reference-DB.
- **iOS-Background-Strategie entscheiden:** BGTaskScheduler /
  `BGProcessingTask`, Push-getriggertes Resume, oder bewusst als
  „iOS = foreground only" dokumentieren und in der UI klarmachen.
- **iNat-Open-Data fuer Offline-`taxon_id`-Mapping** dort ausbauen, wo
  ETL-Common-Names die Live-Strecke ersetzen.

## ETL vs. Runtime

### Ins ETL verlagern

- `taxon_id`-Aufloesung und externe ID-Mappings (teilweise bereits erledigt)
- Taxonomy-Common-Names mit Regionalisierung (P2)
- stabile Vorberechnungen ohne Laufzeit-Ranking oder Regionalisierung

### Laufzeit/API-gebunden lassen

- Species-Common-Names mit regionaler Priorisierung (bis ETL-Snapshot das
  abdeckt)
- Online-Suche fuer unbekannte Taxa
- kuratierte Fotoauswahl (iNat-API-Qualitaet soll erhalten bleiben)

## Open Data

Das `inaturalist-open-data`-Repo ist als ETL-Quelle interessant, aber kein
vollstaendiger Runtime-Ersatz.

**Gut abgedeckt:** stabile Snapshot-Daten fuer `taxa`, `observations`, `photos`.
Passt fuer Offline-`taxon_id`-Mappings in `entity_external_ids`.

**Nicht gleichwertig ersetzt:**

- *Common Names:* Sprachzuordnung, mehrere Kandidaten je Sprache, `position`-
  Ranking und `place_taxon_names`-Priorisierung sind in der Open-Data-Doku
  nicht als stabiler Ersatz verifiziert.
- *Bilder:* Die kuratierte `taxon_photos`-Auswahl und Observation-Fallbacks
  bräuchten eine eigene Heuristik; das ist kein Drop-In.

## Zielbild

1. ETL ist primaere Quelle fuer `entity_external_ids` und perspektivisch fuer
   Taxonomy-Common-Names mit Regionalisierung.
2. Runtime nutzt gespeicherte IDs bevorzugt und persistiert Synonym-Aufloesungen,
   sodass Live-Resolves auf echte Misses beschraenkt bleiben.
3. Species-Common-Names bleiben hybrid, bis ein V2- oder Open-Data-Ersatz
   fachlich ausreichend ist.
4. Foto-Enrichment bleibt iNat-API-basiert, mit weniger Fallback-Stufen.
5. UX zeigt Quick-Pass-Ready prominent, laesst den Banner bei `retryScheduled`
   sichtbar und macht Permanent-Failures recover-bar.

## Exit-Condition fuer den Legacy-Common-Name-Pfad

`www.inaturalist.org/taxon_names.json` kann erst ersetzt werden, wenn
mindestens eine der folgenden Bedingungen erfuellt ist:

1. Ein offizieller V2-Endpunkt liefert Sprachzuordnung, Position-Ranking und
   `place_taxon_names`-Priorisierung gleichwertig.
2. Oder Open Data liefert dieselben Eigenschaften in reproduzierbarer Form.
3. Oder die Reference-DB liefert Common Names mit regionaler Priorisierung in
   ausreichender Abdeckung, sodass der Live-Pfad nur noch fuer echte Misses
   gebraucht wird.
