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
- Quellen, die nur ergänzen und ohne die ein Build trotzdem eine brauchbare
  Referenz-DB ergibt, sagen das im Manifest (`optional: true`, sonst
  `false`). `--no-enrich` überspringt nur diese — und mit ihnen jede Quelle,
  die von einer übersprungenen abhängt —, nicht alle ergänzenden Quellen. Das
  Merkmal fragt bewusst nicht, ob eine Quelle Netzwerk braucht: FishBase und
  SeaLifeBase laden zur Build-Zeit ebenfalls herunter, sind aber die
  Grundlage jedes Builds und dürfen nicht entfallen.

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
liefert keine Einordnung. FishBase und SeaLifeBase bekommen ihre Werte deshalb
mit dem Feld selbst (Schritt 1 der [Umsetzung](#umsetzung)), nicht erst, wenn
eine weitere Quelle Einordnungen liefert — sonst wäre der erste Build danach
blockiert. Kommt ein weiterer Beitragstyp mit nur einem gültigen Wert hinzu,
bekommt er ein eigenes Feld nach demselben Muster.

---

## Abgleich

Ob ein Datensatz einer Quelle eine schon vorhandene Entität meint, entscheidet
eine gemeinsame Funktion in `core/`, nicht jedes Plugin für sich:

1. über eine **externe ID**, die beide Seiten kennen (`entity_external_ids`,
   z. B. eine WoRMS-AphiaID; zur Abgrenzung vom Register siehe
   [Quellenschlüssel und externe IDs](#quellenschlüssel-und-externe-ids));
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

### Fehlende und mehrdeutige Zuordnungen

Was mit einem Datensatz ohne eindeutige Entität geschieht, hängt davon ab, wem
der Fehler gehört:

- **Eigene, von Hand gepflegte Daten** (`curated`) brechen den Build ab. Eine
  Zeile, die keine Entität trifft, ist ein Fehler in unserer eigenen Datei und
  wird dort behoben, bevor eine Referenz-DB entsteht.
- **Externe Quellen** schreiben fehlende und mehrdeutige Zuordnungen in den
  Build-Bericht und bauen weiter. Ihre Daten können wir nicht korrigieren;
  dass ein Teil davon keinen Partner findet, ist der Normalfall.

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

- **Wer Existenz liefert, liefert einen Schlüssel.** Eine Quelle, die sagt
  „diese Entität gibt es“ — ob sie sie anlegt oder der Abgleich sie findet —,
  muss für jede solche Entität einen stabilen Quellenschlüssel liefern: eine
  Nummer oder Kennung, die in ihren eigenen Daten über Releases gleich bleibt.
  Eine Quelle, die nur Beiträge an Entitäten hängt, die sie über den
  Schlüssel einer anderen Quelle adressiert (die kuratierten Klassennamen
  über die FishBase-ClassNum), trägt keinen Schlüssel ein und hält damit auch
  keine Entität am Leben.
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

### Quellenschlüssel und externe IDs

Zwei Tabellen ordnen Entitäten fremden Kennungen zu, mit verschiedenem Zweck:

- **`entity_source_keys`** — *woher ein Datensatz kommt*: der Schlüssel des
  Datensatzes in der importierenden Quelle (FishBase-SpecCode,
  SeaLifeBase-SpecCode, …). Er vergibt und hält die ID und trägt den
  Lebenszyklus. Geschrieben vom Build, gelesen von keinem Plugin direkt.
- **`entity_external_ids`** — *wie andere Systeme die Entität nennen*: fachliche
  Querverweise wie die iNaturalist-Taxon-ID, eine WoRMS-AphiaID oder ein
  GBIF-Key. Sie dienen dem Abgleich und der App (Links, Abfragen bei
  iNaturalist). Jede Quelle darf welche beitragen.

Eine Quelle kann in beiden stehen: Würde WoRMS als Quelle angebunden, wäre die
AphiaID ihr Quellenschlüssel *und* ein Querverweis. Die Tabellen bleiben
trotzdem getrennt, weil die eine Identität und Lebenszyklus regelt und die
andere nur Auskunft gibt.

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
| `flashcard_stats` | `species_id`, roh | eine Zeile bleibt, gewählt nach `last_review_date` absteigend (NULL zuletzt), dann `next_review_date` absteigend (NULL zuletzt), dann die Zeile mit der kleineren alten ID |
| `enrichment_species_work` | `species_id`, roh | die vorhandene Zeile bleibt, Consent-Flags ODER-verknüpft |
| `enrichment_species_capability_state` | `species_id`, roh | Zeile löschen; die Anreicherung plant neu |
| `enrichment_species_deck_membership` | `species_id`, roh | Duplikat verwerfen |
| `enrichment_taxonomy_work_species` | `species_id`, roh | Duplikat verwerfen |
| `inat_photo_cache` | `species_id`, roh | Duplikat verwerfen |
| `species_photo_gap_ack` | `species_id`, roh | Duplikat verwerfen |
| `external_identifier_cache` | `entity_id`, roh bei Arten (höhere Taxa: `rang:name`, nicht betroffen) | die vorhandene Zeile bleibt |
| `runtime_common_names` | `entity_key`, `species:<id>` bei Arten | kein Primärschlüssel; Duplikate sind Zeilen mit gleichem `entity_key`, `language_code`, `name` und `place_id` (NULL gleich NULL), davon bleibt die mit dem jüngsten `fetched_at` |
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
| Quelle als Plugin mit Manifest und `sources`-Eintrag | ja, für FishBase, SeaLifeBase und die kuratierten Ergänzungen (`curated`) |
| Beiträge mit `source` | ja (`common_names`, `pictures`, `taxonomy_traits`, …) |
| Weiches Löschen von Arten | ja, je Quelle für ihre eigenen Arten |
| `depends_on_sources` und Sortierung | ja — `core/plugin_order.sh`; `--plugin` nimmt Abhängigkeiten mit |
| `placement_priority` | ja als Feld — FishBase 10, SeaLifeBase 20, geprüft auf Ganzzahl und Eindeutigkeit; die Einordnung kommt noch allein von der Quelle, die die Art anlegt |
| Abgleich in `core/` | nein — FishBase und SeaLifeBase legen über ihre eigenen Nummern an und überschneiden sich nicht |
| IDs ohne Quelle, Register (`entity_source_keys`) | nein — IDs werden berechnet und tragen die Quelle (`discere:fishbase_species:<nr>`); `schema.sql` prüft das Format mit `GLOB 'discere:*_*:*'` |
| Aliase | nein |
| `optional` im Manifest | ja — `--no-enrich` überspringt optionale Quellen samt Abhängigen, außerdem Stage 01b und Stage 03; keine Quelle ist optional |
| iNaturalist-Zuordnung | als Sonderweg in Stage 03 (`enrichment/inaturalist/`), ohne Manifest und `sources`-Eintrag |

---

## Umsetzung

### Übergang: nur Beiträge

Bis Register und Aliase stehen, dürfen weitere Quellen **nur Beiträge zu
vorhandenen Entitäten** liefern und keine Entitäten anlegen. Fehlt eine
Entität, gilt die Regel aus
[Fehlende und mehrdeutige Zuordnungen](#fehlende-und-mehrdeutige-zuordnungen).

### Schritte

1. *(umgesetzt)* **`depends_on_sources` und Sortierung** in `build.sh`, dazu
   `optional` und `placement_priority` mit eigenen Werten für FishBase und
   SeaLifeBase.
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
`depends_on_sources: [fishbase, sealifebase]` und `optional: true`; Stage 03
entfällt.

---

## Beispiele

| Quelle | Liefert | Legt Arten an |
|---|---|---|
| Kuratierte Klassennamen | Namen de/fr/es für FishBase-Klassen ohne iNaturalist-Gegenstück | nein |
| iNaturalist | externe IDs | nein |
| WoRMS | AphiaID, Lebensraum-Flags, gültiger Name | nein |
| Crab Database | englische Namen, Synonyme, Fotos; Krabbenarten, die SeaLifeBase fehlen | ja — erst nach Schritt 5; dazu fehlt heute die Lizenz („All rights reserved“) |
