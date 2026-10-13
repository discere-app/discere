# Datenquellen: Konzept

Beschreibt, wie das ETL mit mehreren Datenquellen umgeht, die dieselben Arten
und Taxa betreffen: Quellen, die vorhandene Daten ergänzen (Namen, Synonyme,
Bilder, Merkmale), und Quellen, die zusätzlich eigene Arten mitbringen.

Das Dokument ist ein **Zielbild**. Was davon heute schon gilt, steht in
[Ist-Zustand](#ist-zustand); den Weg dorthin beschreibt
[Umsetzung](#umsetzung). Der aktuelle Plugin-Vertrag steht in
[`plugin-system.md`](plugin-system.md).

---

## Begriffe

- **Quelle** — ein Plugin unter `plugins/<name>/` mit Manifest,
  Strukturprüfung und einem Eintrag in `sources` (Lizenz, Zitierung). Das gilt
  auch für eigene Pflege, etwa von Hand kuratierte Namen: Sie ist eine Quelle
  wie jede andere.
- **Entität** — eine Art oder ein höheres Taxon in der Referenz-DB. Eine
  Entität ist ein **neutraler Anker**: Sie gehört keiner Quelle.
- **Beitrag** — alles, was eine Quelle zu einer Entität liefert: dass es sie
  gibt, ihre Einordnung, Namen, Synonyme, Bilder, Merkmale, Verbreitung,
  externe IDs. Jeder Beitrag trägt die `source` der Quelle, die ihn
  geschrieben hat.

Es gibt nur eine Beziehung: Eine Quelle liefert Beiträge zu Entitäten.
Einen Besitzer, der eine Entität exklusiv hält, gibt es nicht.

---

## Was eine Quelle darf

- **Beiträge zu jeder Entität liefern**, auch zu Entitäten, die andere
  Quellen zuerst geliefert haben. Geschrieben wird nur in Tabellen mit
  `source`-Spalte.
- **Neue Entitäten anlegen**, wenn der [Abgleich](#abgleich) keinen Treffer
  findet. Das Anlegen ist selbst nur ein Beitrag („diese Art gibt es“); die
  neue Entität gehört der Quelle danach nicht.
- **Beim Neuimport nur eigene Beiträge löschen** (`WHERE source = '<quelle>'`).
  Entitäten selbst löscht keine Quelle (siehe [Lebenszyklus](#lebenszyklus)).

---

## Abhängigkeiten und Reihenfolge

- Das Manifest nennt die Quellen, gegen deren Daten abgeglichen wird, in
  `depends_on_sources`. Das bestehende Feld `requires` bleibt den
  Werkzeugen vorbehalten, die ein Plugin zum Laufen braucht (`duckdb`,
  `sqlite3`, `curl`):

  ```yaml
  requires:
    - sqlite3
  depends_on_sources:
    - fishbase
  ```

- `build.sh` sortiert die Plugins danach und bricht bei einem Zyklus oder
  einer fehlenden Abhängigkeit ab. Quellen ohne Abhängigkeit untereinander
  laufen in alphabetischer Reihenfolge, damit jeder Build dieselbe Reihenfolge
  hat. Ein Teilbuild mit `--plugin <name>` nimmt die Abhängigkeiten mit.
- Die Reihenfolge regelt nur, *wann* eine Quelle läuft — nicht, wessen Beitrag
  gilt. Wo nur ein Wert gelten kann, entscheidet eine ausdrückliche
  [Rangfolge](#rangfolge).
- Quellen, die zur Build-Zeit Netzwerk brauchen, sagen das im Manifest
  (`network: true`). `--no-enrich` überspringt nur diese, nicht alle
  ergänzenden Quellen.

### Rangfolge

Die meisten Beiträge stehen gleichberechtigt nebeneinander: Namen, Synonyme,
Bilder und Merkmale tragen ihre `source`, und mehrere Quellen dürfen
gleichzeitig welche liefern. Eine Rangfolge braucht es nur für Beiträge, von
denen genau einer gelten kann — heute die [Einordnung](#einordnung).

Dafür nennt eine Quelle, die Einordnungen liefert, im Manifest ihren Rang:

```yaml
placement_priority: 10   # kleiner = gewichtiger
```

Zwei Quellen mit demselben Wert brechen den Build ab; eine Quelle ohne Wert
liefert keine Einordnung. Kommt ein weiterer Beitragstyp mit nur einem
gültigen Wert hinzu, bekommt er ein eigenes Feld nach demselben Muster.

---

## Abgleich

Ob ein Datensatz einer Quelle eine schon vorhandene Entität meint, entscheidet
eine gemeinsame Funktion in `core/`, nicht jedes Plugin für sich:

1. über eine **externe ID**, die beide Seiten kennen (`entity_external_ids`,
   z. B. eine WoRMS-AphiaID);
2. sonst über den **wissenschaftlichen Namen samt Synonymen**, auf demselben
   Rang. Grundlage sind alle Namen in `species_scientific_names` als
   Kandidaten, nicht `species_name_lookup`: Diese Tabelle ist schon
   disambiguiert (ein Gewinner je Name, für die Namensauflösung der App) und
   würde eine Mehrdeutigkeit verdecken, die der Abgleich sehen muss;
3. ist das Ergebnis **mehrdeutig, gibt es keinen Treffer**, sondern einen
   Eintrag im Build-Bericht. Geraten wird nie: Ein sichtbares Doppel lässt sich
   zusammenführen, zwei vermischte Arten lassen sich kaum wieder trennen.

Ein Treffer heißt: Die Quelle hängt ihre Beiträge an. Kein Treffer heißt: Die
Quelle legt die Entität an und hängt sie unter einen Elternteil, den sie über
denselben Abgleich findet oder selbst anlegt.

---

## Identität

### IDs tragen keine Quelle

Eine ID ist ein Name ohne Bedeutung: `discere:species:<nr>`. Sie sagt nicht,
welche Quelle die Entität zuerst geliefert hat, und sie ändert sich nie.

### Das Register vergibt IDs stabil

Das ETL baut die Referenz-DB bei jedem Lauf neu (`create_db.sh --force`).
Stabile IDs kann es deshalb nicht aus dem Datenstand eines Builds ableiten:
Liefert eine zweite Quelle später dieselbe Art und läuft im nächsten Build
zuerst, entstünde sonst eine andere ID.

Ein **ID-Register** hält über alle Releases fest, welcher Quellenschlüssel zu
welcher ID gehört. Es ist eine Tabelle in der Referenz-DB selbst:

```
entity_source_keys(source, entity_type, external_id → entity_id, active)
```

- **Viele Schlüssel, eine ID.** Jede Quelle, die eine Entität liefert, hat
  ihren eigenen Schlüssel darauf. Findet der Abgleich für Quelle B eine
  Entität, die Quelle A angelegt hat, wird B's Schlüssel auf die bestehende ID
  eingetragen — es entsteht keine neue.
- **Schlüssel verfallen nicht.** Ein Schlüssel, den seine Quelle in einem
  Release nicht mehr liefert, bleibt mit `active = 0` stehen. Taucht er später
  wieder auf, bekommt er seine alte ID zurück.
- **`active` ist die Lieferung dieses Builds.** Jeder Build setzt `active`
  für genau die Schlüssel, die seine Quellen geliefert haben. Daraus folgt der
  [Lebenszyklus](#lebenszyklus).

Ein Build lädt das zuletzt veröffentlichte Release (in `discere-data`, lokal
zwischengespeichert) und übernimmt dessen `entity_source_keys`. IDs vergibt er
nur für Entitäten, die weder ein bekannter Schlüssel noch der Abgleich trifft,
und schreibt das fortgeschriebene Register in die neue DB. Das Register reist
damit im Release mit: Es ist genau der Stand, den die Nutzer haben, und es gibt
kein zweites Artefakt, das davon abweichen könnte.

Ohne lesbares letztes Release bricht der Build ab — sonst würden IDs neu
vergeben und die Lernstände der Nutzer zeigten ins Leere. Fehlt dem letzten
Release die Tabelle noch, wird sie einmalig aus dessen IDs abgeleitet, die die
Quelle enthalten (`discere:<quelle>_<typ>:<nr>`).

### Aliase führen Entitäten zusammen

Erweisen sich zwei Entitäten als dieselbe Art — ein Abgleich hat sie verfehlt,
oder eine Quelle schließt die Lücke später —, bleibt eine ID gültig und die
andere wird zum Alias:

- Die Referenz-DB führt `entity_aliases(alias_id → entity_id)`.
- Die App schreibt beim Wechsel auf eine neue Referenz-DB alle Verweise von
  Alias-IDs auf die gültige ID um, bevor sie die neue DB benutzt: in einer
  Transaktion, idempotent, bei angehaltener Anreicherung.
- Die Alias-ID bleibt **nicht** als eigene Zeile in `species` stehen; die
  Alias-Tabelle ist ihr Nachweis. Bei der Umstellung aller IDs (siehe
  [Umsetzung](#umsetzung)) würde sich die Artentabelle sonst verdoppeln.

Betroffen sind die Tabellen der Nutzer-DB, die IDs aus der Referenz-DB
speichern. Fallen zwei IDs auf eine zusammen, kann das Umschreiben mit dem
Primärschlüssel kollidieren; dafür gilt je Tabelle eine Regel:

| Tabelle | Spalte, Form | Bei Kollision |
|---|---|---|
| `flashcard_stats` | `species_id`, roh | die Zeile mit der jüngsten Wiederholung bleibt |
| `enrichment_species_work` | `species_id`, roh | die vorhandene Zeile bleibt, Consent-Flags ODER-verknüpft |
| `enrichment_species_capability_state` | `species_id`, roh | Zeile löschen; die Anreicherung plant neu |
| `enrichment_species_deck_membership` | `species_id`, roh | Duplikat verwerfen |
| `enrichment_taxonomy_work_species` | `species_id`, roh | Duplikat verwerfen |
| `inat_photo_cache` | `species_id`, roh | Duplikat verwerfen |
| `species_photo_gap_ack` | `species_id`, roh | Duplikat verwerfen |
| `external_identifier_cache` | `entity_id`, roh bei Arten (höhere Taxa: `rang:name`, nicht betroffen) | die vorhandene Zeile bleibt |
| `runtime_common_names` | `entity_key`, `species:<id>` bei Arten | Duplikat verwerfen |
| `runtime_common_name_search_documents` | `entity_key` und `entity_id` | Dokument neu aufbauen |

Die Matrix ist bei jeder neuen Tabelle der Nutzer-DB, die eine Referenz-ID
speichert, nachzuziehen. Nicht betroffen sind Tabellen, die über Namen oder
Deck-IDs verweisen (`enrichment_taxonomy_work` über `rang:name`,
`enrichment_unresolved_names`, `enrichment_jobs`, `decks`, `deck_config`).
Export, Teilen und QR-Codes enthalten nur wissenschaftliche Namen
(`CreateDeck.toJson`) und sind von einem Alias nicht betroffen.

Eine ältere App, die keine Aliase anwenden kann, darf eine solche Referenz-DB
nicht installieren. Das sichert die Schemaversion im Manifest:
`ReferenceDatabaseProvisioner.supportedSchemaVersion` lehnt jede andere
Version ab.

---

## Einordnung

Jede Quelle, die eine Art kennt, kann ihre Einordnung (Gattung, Familie, …)
als Beitrag liefern. Es gilt die Einordnung der Quelle mit dem kleinsten
`placement_priority` (siehe [Rangfolge](#rangfolge)). Abweichende
Einordnungen anderer Quellen meldet der Build, er übernimmt sie nicht.

## Lebenszyklus

Eine Entität ist aktiv, solange mindestens einer ihrer Schlüssel in
`entity_source_keys` aktiv ist, also mindestens eine Quelle sie in diesem Build
geliefert hat. Ist keiner mehr aktiv, wird sie weich gelöscht
(`status = 'deprecated'`), nie entfernt — Nutzer-Daten können auf sie zeigen.
Das entscheidet ein Schritt nach allen Plugins, nicht jede Quelle für sich.

## Merkmale

Die Spalten mit Merkmalen direkt in `species` (Größe, Tiefe, Lebensraum,
Gefährdung, …) befüllen FishBase und SeaLifeBase. Weitere Quellen schreiben
Merkmale nicht in diese Spalten, sondern nach ihrer Form:

- ein Wert je Entität → `taxonomy_traits` (`source` ist Teil des Schlüssels);
- mehrere Werte je Entität (Länder, Monate, Meeresgebiete) → eine eigene
  Tabelle nach dem Muster von `taxonomy_distribution_regions`;
- sprachabhängige Texte (Beschreibungen) → eine eigene Tabelle nach dem Muster
  von `common_names`.

---

## Lizenz

Eine Quelle wird nur aufgenommen, wenn ihre Lizenz die Weitergabe in der
Referenz-DB erlaubt oder eine schriftliche Erlaubnis vorliegt; die Erlaubnis
wird in `source.sql` vermerkt. Lizenzen je Datensatz (etwa je Bild) führt der
Datensatz selbst, wie heute schon `pictures`.

---

## Ist-Zustand

| Teil des Konzepts | Heute |
|---|---|
| Quelle als Plugin mit Manifest und `sources`-Eintrag | ja, für FishBase und SeaLifeBase |
| Beiträge mit `source` | ja (`common_names`, `pictures`, `taxonomy_traits`, …) |
| Weiches Löschen von Arten | ja, je Quelle für ihre eigenen Arten |
| `depends_on_sources` und Sortierung | nein — Reihenfolge alphabetisch; `requires` im Manifest nennt nur Werkzeuge |
| `placement_priority` | nein — Einordnung kommt allein von der Quelle, die die Art anlegt |
| Abgleich in `core/` | nein — FishBase und SeaLifeBase legen über ihre eigenen Nummern an und überschneiden sich nicht |
| IDs ohne Quelle, Register (`entity_source_keys`) | nein — IDs werden berechnet und tragen die Quelle (`discere:fishbase_species:<nr>`); `schema.sql` prüft das Format mit `GLOB 'discere:*_*:*'` |
| Aliase | nein |
| Netzwerk-Merkmal im Manifest | nein — `--no-enrich` überspringt die ganze Stage 03 |
| iNaturalist-Zuordnung | als Sonderweg in Stage 03 (`enrichment/inaturalist/`), ohne Manifest und `sources`-Eintrag |

---

## Umsetzung

### Übergang: nur Beiträge

Bis Register und Aliase stehen, dürfen weitere Quellen **nur Beiträge zu
vorhandenen Entitäten** liefern und keine Entitäten anlegen. Fehlt eine
Entität, landet der Datensatz im Build-Bericht.

### Schritte

1. **`depends_on_sources` und Sortierung** in `build.sh`, dazu `network`.
   Erster Anwendungsfall: die kuratierten Klassennamen als eigene Quelle mit
   `depends_on_sources: [fishbase]` (#298), die nur Beiträge liefert.
2. **Abgleich in `core/`**, über Kandidaten aus `species_scientific_names`.
3. **Register und Aliase** — samt Umschreiben in der App und neuer
   Schemaversion.
4. **Umstellung aller IDs** auf das Format ohne Quelle: ein Release, in dem
   jede bisherige ID ein Alias auf ihre neue ist. Es erprobt den
   Alias-Mechanismus einmal vollständig, bevor er für einzelne Doppel gebraucht
   wird. Der `GLOB` in `schema.sql` wird dabei auf `'discere:*:*'` gelockert.
5. **Danach** dürfen Quellen Entitäten anlegen.

Unabhängig davon: Die iNaturalist-Zuordnung wird eine Quelle mit
`depends_on_sources: [fishbase, sealifebase]` und `network: true`; Stage 03
entfällt.

---

## Beispiele

| Quelle | Liefert | Legt Arten an |
|---|---|---|
| Kuratierte Klassennamen | Namen de/fr/es für FishBase-Klassen ohne iNaturalist-Gegenstück | nein |
| iNaturalist | externe IDs | nein |
| WoRMS | AphiaID, Lebensraum-Flags, gültiger Name | nein |
| Crab Database | englische Namen, Synonyme, Fotos; Krabbenarten, die SeaLifeBase fehlen | ja — erst nach Schritt 5; dazu fehlt heute die Lizenz („All rights reserved“) |
