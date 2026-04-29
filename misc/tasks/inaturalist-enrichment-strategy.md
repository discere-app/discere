# iNaturalist Enrichment Strategy

## Ziel

Diese Notiz fasst den aktuellen Stand der iNaturalist-Integration,
die Common-Names-Migration auf V2 und die Bewertung des
`inaturalist-open-data`-Repos in einem Dokument zusammen.

## Aktueller Stand

Die iNaturalist-Integration ist aktuell bewusst hybrid:

- `GET /v2/taxa`
- `GET /v2/taxa/{id}`
- `GET /v2/observations`

laufen bereits ueber `api.inaturalist.org/v2`.

Die Common-Name-Strecke laeuft weiterhin ueber:

- `https://www.inaturalist.org/taxon_names.json?taxon_id=<id>&per_page=200`

## Heutiger Ablauf

1. Scientific name / Binomen -> `GET /v2/taxa`
2. `taxon_id` aus Match aufloesen
3. Bilder laden ueber:
   - `GET /v2/taxa/{taxon_id}`
   - `GET /v2/observations?...quality_grade=research`
   - optionalen zweiten Observation-Fallback ohne `quality_grade`
4. Common Names laden ueber:
   - `GET /taxon_names.json?taxon_id=<id>&per_page=200`

## Warum Common Names noch nicht auf V2 migriert sind

Fuer `taxon_names.json` gibt es aktuell keinen verifizierten,
dokumentierten V2-Ersatz, der dieselbe Funktionalitaet fachlich sicher
abdeckt.

Relevant sind insbesondere:

- lokalisierte Common Names
- mehrere Kandidaten pro Sprache
- Ranking ueber `position`
- ortsbezogene Priorisierung ueber `place_taxon_names`

Solange kein belastbarer V2-Endpunkt diese Daten in ausreichender Form
liefert, bleibt der Legacy-Pfad absichtlich bestehen.

## Wichtigste Erkenntnisse zum aktuellen Enrichment

### 1. `taxon_names.json` ist der empfindlichste Pfad

- In Logs und Telemetrie war dieser Pfad der haeufigste Kandidat fuer `429`
  und `Timeout`.
- Der Pfad haengt an `www.inaturalist.org`, nicht an der modernen
  `api.inaturalist.org/v2`-Schiene.
- Er wirkt damit wie ein aelterer und fragilerer Web-Endpunkt.

### 2. Common-Name-Requests koennen fachlich stark anwachsen

- nicht nur pro Species
- sondern auch fuer `genus`, `family`, `order`, `class`
- trotz Dedupe bleibt das eine grosse Menge kleiner Requests

### 3. `GET /v2/taxa/{id}` wird heute weitgehend species-bezogen genutzt

- aktuell im Wesentlichen ein Detail-Call pro Species, wenn Fotos gebraucht
  werden
- laut offizieller V2-OpenAPI ist der `id`-Pfadparameter dort als Array
  modelliert
- das deutet darauf hin, dass mehrere IDs in einem Request moeglich sein
  koennten und geprueft werden sollten

## Was bereits verbessert wurde

- importweite und persistente Dedupe fuer Species und Taxonomy
- `taxon_id`-Memoisierung
- verschachtelte `fields` fuer `taxa` ueber
  `POST + X-HTTP-Method-Override: GET`
- schlankere Taxon-Suche mit direkt nutzbaren Zusatzfeldern wie
  `iconic_taxon_name` und `default_photo`
- Batch-Nutzung fuer `GET /v2/taxa/{id1,id2,...}` bei bereits bekannten
  `taxon_id`s
- In-Memory-Cache fuer bereits geladene Taxon-Details
- getrennte Stages fuer Species- und Taxonomy-Common-Names
- Backoff mit Jitter statt Hot-Loops
- weniger Queue- und Notification-Churn
- bessere Diagnostik fuer degradierte Runs

## Weitere sinnvolle Optimierungen

### A. `taxon_names.json` defensiver behandeln

- Species-Common-Names hoeher priorisieren
- Taxonomy-Common-Names spaeter oder optional behandeln
- bei `429` und `Timeout` frueher und laenger in Cooldown gehen

### B. Observation-Fallback restriktiver machen

- der zweite `observations`-Call ohne `quality_grade` tauscht Qualitaet gegen
  Abdeckung
- dieser Schritt ist request-teuer und sollte bewusst priorisiert werden

### C. Batch-Nutzung fuer `GET /v2/taxa/{id}` pruefen

- wenn mehrere `taxon_id`s bereits bekannt sind, koennte man Taxon-Details
  eventuell gesammelt laden
- das wuerde weitere Einzelrequests sparen

Status:

- inzwischen umgesetzt fuer bekannte IDs
- reduziert den Request-Druck im Foto-Enrichment, loest aber nicht das
  vorgelagerte Problem der Namensaufloesung

### D. Species-Aufloesung deduplizieren und als Resolve-Plan vorziehen

- aktuell wird ein wissenschaftlicher Name in verschiedenen Enrichment-Phasen
  potenziell mehrfach gegen `/v2/taxa?q=...` aufgeloest
- fachlich funktioniert das, ist aber unnoetig request-intensiv
- ein sinnvoller naechster Schritt waere eine vorgelagerte Resolve-Phase:
  - eindeutige `(rank, scientific_name)`-Paare sammeln
  - Reference-DB und Runtime-Cache zuerst auslesen
  - nur echte Misses live aufloesen
  - erfolgreiche `taxon_id`s sofort wiederpersistieren
  - nachgelagerte Foto- und Common-Name-Stufen nur noch per `taxon_id`
    arbeiten lassen

Wichtig:

- das ist kein echter API-Batch fuer mehrere Namen in einem Request
- laut bisherigem Stand bietet V2 dafuer keinen verifizierten Multi-Name-
  Resolve-Endpunkt
- der Gewinn kommt daher aus Orchestrierung, Dedupe und Wiederverwendung,
  nicht aus einem einzelnen grossen API-Call

### E. Observation-Felder ebenfalls auf Nested `fields` umstellen

- bei `taxa` ist bereits verifiziert, dass verschachtelte Daten ueber
  `POST + X-HTTP-Method-Override: GET` sauber und deutlich schlanker geladen
  werden koennen
- fuer `/v2/observations` ist derselbe Umbau naheliegend, insbesondere fuer
  `observation_photos.photo`
- das ist ein Effizienzthema, kein funktionaler Blocker

### F. Synonym-Faelle gezielt persistieren

- Live-Stichproben zeigen, dass Eingabename und akzeptierter Taxon-Name
  auseinanderfallen koennen
- Beispiel:
  - `Metasepia pfefferi` matcht auf einen akzeptierten Taxon-Namen
    `Ascarosepion pfefferi`
- aktuell funktioniert der Pfad fachlich bereits
- zusaetzlich sinnvoll waere, solche Synonym-Aufloesungen bewusster als
  stabile Mapping-Information zu persistieren, damit dieselben Faelle spaeter
  nicht erneut live aufgeloest werden muessen

## Kurzfazit zum aktuellen Zustand

Das Enrichment ist fachlich derzeit benutzbar:

- V2-Suche und V2-Detail-Endpunkte funktionieren
- Nested Taxon-Fields funktionieren
- Batch-Detail-Requests fuer bekannte IDs funktionieren
- die relevante Testkette laeuft gruenn

Die wichtigsten offenen Punkte sind im Moment vor allem Effizienzthemen:

- vorgelagerte deduplizierte Namensaufloesung
- weitere Payload-Reduktion bei `observations`
- defensivere Behandlung des fragilen `taxon_names.json`-Pfads

## Open-Data-Bewertung

Das Repo `inaturalist-open-data` ist fuer einen Teil des Enrichments
interessant, aber kein vollstaendiger Ersatz fuer die heutige API-Nutzung.

### Was Open Data gut abdeckt

- grosse, stabile Snapshot-Daten fuer `taxa`, `observations`, `photos`,
  `projects` und weitere Metadaten
- gute Grundlage fuer ETL-seitige Vorverarbeitung
- besonders geeignet fuer Offline-Mappings zwischen Discere-Entities und
  iNaturalist-Taxon-IDs

Das passt bereits zum aktuellen Aufbau:

- `etl/enrichment/inaturalist/enrich.sh` nutzt `taxa.csv.gz`
- Ziel ist `entity_external_ids` als Offline-Bruecke zu iNaturalist

### Was Open Data aktuell nicht gleichwertig ersetzt

#### Common Names

Der aktuelle Runtime-Pfad nutzt fachliche Eigenschaften, die in der Open-Data-
Doku nicht als gleichwertiger Ersatz sichtbar sind:

- Sprachzuordnung
- mehrere Kandidaten pro Sprache
- globales Ranking ueber `position`
- ortsbezogene Priorisierung ueber `place_taxon_names`

Solange diese Eigenschaften nicht aus einem verifizierten, stabilen
Open-Data-Pfad reproduzierbar vorliegen, ist Open Data kein 1:1-Ersatz fuer
die heutige Common-Name-Strecke.

#### Bilder

Der aktuelle Bildpfad nutzt:

- kuratierte `taxon_photos` aus `GET /v2/taxa/{id}`
- Observation-Fallbacks fuer weitere Bilder
- Lizenzfilter und Priorisierung

Mit Open Data koennte man wahrscheinlich Foto-Kandidaten im ETL
vorberechnen, aber nicht automatisch dieselbe kuratierte Auswahl wie heute
reproduzieren. Dafuer waere eine eigene Heuristik noetig.

## Architektur-Fazit

### Ja, ins ETL verlagern

- `taxon_id`-Aufloesung und externe ID-Mappings
- weitere stabile Vorberechnungen, die keine Laufzeit-Rankings oder
  Regionalisierung brauchen
- optional vorberechnete Foto-Kandidaten, falls eine eigene Auswahlheuristik
  akzeptiert wird

### Vorlaeufig Laufzeit/API-gebunden lassen

- Common Names mit Ranking und regionaler Priorisierung
- Online-Suche fuer unbekannte Taxa
- kuratierte Fotoauswahl, sofern die iNaturalist-API-Qualitaet erhalten
  bleiben soll

## Zielbild

Der saubere Schnitt fuer Discere waere:

1. ETL bleibt die primaere Quelle fuer `entity_external_ids`.
2. Runtime nutzt diese IDs bevorzugt und vermeidet unnnoetige Live-Resolves.
3. Common Names bleiben vorerst hybrid, bis ein verifizierter V2- oder
   Open-Data-Ersatz fachlich ausreichend ist.
4. Foto-Enrichment kann spaeter teilweise ins ETL verschoben werden, aber nur
   mit klarer Produktentscheidung zur Auswahlheuristik.

## Exit-Conditions fuer eine vollstaendige Bereinigung

Diese Baustelle ist erst wirklich abgeschlossen, wenn mindestens eine der
folgenden Bedingungen erfuellt ist:

1. Ein offizieller, dokumentierter V2-Endpunkt fuer Common Names ist
   verifiziert.
2. Oder es gibt einen belastbaren Open-Data-Weg, der die benoetigten
   Eigenschaften fuer Common Names reproduzierbar liefert.
3. Oder es gibt eine bewusste Produktentscheidung, auf Teile der heutigen
   Funktionalitaet zu verzichten, insbesondere bei Ranking oder regionaler
   Priorisierung.

Erst dann sollte `INaturalistService.fetchCommonNames(...)` keinen
`www.inaturalist.org/taxon_names.json`-Pfad mehr verwenden.
