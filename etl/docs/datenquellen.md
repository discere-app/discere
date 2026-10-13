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
4. treffen **mehrere Datensätze einer Quelle dieselbe Entität** — auch einer,
   der selbst mehrdeutig ist —, behält sie nur der, der sie eindeutig über
   ihren akzeptierten Namen trifft; die übrigen sind mehrdeutig. Führt die
   Quelle den akzeptierten Namen einer Art als eigenen Datensatz, meint sie
   mit einem Synonym dieser Art ein anderes Taxon. So hat eine Entität je
   Quelle höchstens einen Treffer.

Falsch angewandte Namen (`name_status = 'misapplied name'`) sind keine
Kandidaten: Ein solcher Name meint per Definition ein anderes Taxon und belegt
deshalb keine Identität. Mehrdeutige Synonyme (`ambiguous synonym`) bleiben
Kandidaten; trifft ein Name mehrere Arten, greift Regel 3.

Namen werden verglichen wie `species_scientific_names.normalized_name`:
klein geschrieben, ohne Leerzeichen am Rand. Höhere Taxa gleicht der Abgleich
über den Namen in der Tabelle ihres Rangs ab. Den Weg über externe IDs braucht
bisher keine Quelle; er käme als eigener Kandidatenweg vor dem Namen hinzu.
Mehrdeutigkeit in der Quelle selbst — zwei Datensätze mit gleichem Namen und
Rang, etwa Homonyme über Reiche hinweg — erkennt das Plugin, bevor es
abgleicht: Diese Datensätze bekommen keine Zuordnung und stehen im
Build-Bericht.

Umgesetzt ist der Abgleich in `core/sql/match.sql`, für Plugins aufrufbar
über `match_records` in `core/match.sh`.

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

### Build-Bericht

`build.sh` legt für jeden Build neben der Ausgabe-DB ein Verzeichnis
`<db ohne Endung>.build-report/` an. Darin schreibt jede Quelle über
`plugin_report` eine TSV `<quelle>.tsv` mit den Spalten Quelle, Kategorie
(`none`, `ambiguous`), Schlüssel, Name und Detail. Vor der Validierung steht
im Log je Quelle die Anzahl je Kategorie. Läuft ein Plugin ohne `build.sh`,
zählt es seine Einträge nur und meldet die Zahl im Log.

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

Umgesetzt ist das in der Identitäts-Stage (`core/identity.sh`, Stage 02b von
`build.sh`), die nach allen Plugins läuft. Die Plugins schreiben
**vorläufige IDs** mit Quelle (`discere:fishbase_species:6509`); die Stage
ersetzt sie in der ganzen Referenz-DB durch die endgültigen:

- **Schlüssel bekannt** — die registrierte ID.
- **Art mit unbekanntem Schlüssel** — Abgleich gegen die Arten anderer
  Quellen, die in diesem Build schon eine Entität haben, je Quelle in der
  Reihenfolge ihrer `placement_priority`. Ein eindeutiger Treffer ist dieselbe
  Entität: Der Schlüssel kommt auf die bestehende ID, die Zeilen gehen
  zusammen (siehe [Einordnung](#einordnung)). Kein oder ein mehrdeutiger
  Treffer ergibt eine neue Entität, ein mehrdeutiger dazu einen Eintrag im
  Build-Bericht (Quelle `identity`).
- **Höheres Taxon mit unbekanntem Schlüssel** — eine neue Entität. Siehe
  [Bekannte Grenzen](#bekannte-grenzen).
- **Neue IDs** zählen je Typ ab der größten Nummer, die Register, Aliase oder
  Vorgänger schon verwenden, in der Reihenfolge Quelle, dann Schlüssel
  (numerische nach ihrem Wert vor den übrigen). Zwei Builds aus gleichen
  Daten und gleichem Vorgänger vergeben dieselben IDs.

Typnamen im Register sind `species`, `genus`, `family`, `order` und `class`.
Eine Quelle, die Entitäten liefert, braucht eine `placement_priority`; fehlt
sie, bricht die Stage ab.

Beiträge, deren Entität keine Quelle geliefert hat (FishBase führt
Verbreitungsdaten und Volksnamen zu SpecCodes ohne Art), haben keine ID, auf
die sie umgeschrieben werden könnten, und entfallen; leere Verweise
(`''` aus dem CSV-Import) werden `NULL`. Beides zählt das Log.

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

Ohne lesbares letztes Release bricht der Build ab, bevor er eine DB anlegt —
sonst würden IDs neu vergeben und die Lernstände der Nutzer zeigten ins Leere.
`build.sh --initial` baut ausdrücklich ohne Vorgänger und ist nur für Tests und
einen allerersten Build gedacht. Fehlt dem letzten Release die Tabelle noch,
wird sie einmalig aus dessen IDs abgeleitet, die die Quelle enthalten
(`discere:<quelle>_<typ>:<nr>`): Jeder Schlüssel bekommt eine neue ID ohne
Quelle, und jede alte ID wird zum Alias auf ihre neue.

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
- Jeder Alias zeigt **direkt** auf eine existierende Entität. Der Build führt
  die Aliase des Vorgängers auf die aktuelle ID ihres Ziels nach, damit auch
  eine App, die Releases überspringt, in einem Schritt umschreibt. Er prüft:
  keine Alias-ID ist zugleich Entitäts-ID, jedes Ziel existiert, es gibt keine
  Ketten.

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

Liefern zwei Quellen dieselbe Art, bleibt deren Zeile in `species` — samt
Gattung und Kernspalten — die der gewichtigeren Quelle. Alle Beiträge der
anderen Zeile (Namen, Synonyme, Bilder, Merkmale, Verbreitung, externe IDs)
hängen danach an der gemeinsamen ID. Belegen beide denselben Schlüssel einer
Tabelle (etwa je eine iNaturalist-ID für die Art), bleibt der Beitrag der
gewichtigeren Quelle. Weicht die Kette Gattung › Familie › Ordnung › Klasse
(nach Namen) ab, steht das im Build-Bericht (Kategorie `placement`).

## Lebenszyklus

Eine Entität ist aktiv, solange mindestens einer ihrer Schlüssel in
`entity_source_keys` aktiv ist, also mindestens eine Quelle sie in diesem Build
geliefert hat. Ist keiner mehr aktiv, wird sie weich gelöscht
(`status = 'deprecated'`), nie entfernt — Nutzer-Daten können auf sie zeigen.
Das entscheidet ein Schritt nach allen Plugins, nicht jede Quelle für sich.

Weil jeder Build die DB neu anlegt, übernimmt die Identitäts-Stage solche
Entitäten aus dem Vorgänger: die Zeile selbst (Arten mit `status =
'deprecated'` und `deprecated_at`, das schon gesetzte bleibt), ihre
wissenschaftlichen Namen und Volksnamen. Das gilt für jeden Typ, auch für
höhere Taxa, die keinen Status haben; so bleibt die Elternkette jeder
übernommenen Art vollständig, und die App kann Gattung und Epitheton anzeigen.
Bilder, Merkmale, Verbreitung und externe IDs kommen nicht mit.

Ein Teilbuild (`build.sh --plugin …`) liefert nur die Schlüssel seiner
Quellen; alle anderen Entitäten des Vorgängers sind darin übernommen und
deprecated. Ein Release entsteht deshalb nur aus einem vollständigen Build.

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
| Weiches Löschen von Arten | ja — die Identitäts-Stage übernimmt Entitäten ohne aktiven Schlüssel aus dem Vorgänger, Arten als `deprecated` |
| `depends_on_sources` und Sortierung | ja — `core/plugin_order.sh`; `--plugin` nimmt Abhängigkeiten mit |
| `placement_priority` | ja — FishBase 10, SeaLifeBase 20; entscheidet, welche Zeile gilt, wenn zwei Quellen dieselbe Art liefern. Pflicht für jede Quelle, die Entitäten liefert |
| Abgleich in `core/` | ja — `core/match.sh`/`core/sql/match.sql`, über Namen samt Synonymen; genutzt von `inaturalist` und von der Identitäts-Stage für Arten mit unbekanntem Schlüssel |
| Build-Bericht | ja — `<db>.build-report/`, eine TSV je Quelle |
| IDs ohne Quelle, Register (`entity_source_keys`) | ja — Identitäts-Stage (`core/identity.sh`); Plugins schreiben vorläufige IDs mit Quelle, das Release trägt nur `discere:<typ>:<nr>`. `schema.sql` lässt beide Formen zu (`GLOB 'discere:*:*'`), die Validierung nur die endgültige |
| Aliase | ja im ETL (`entity_aliases`, jede abgelöste ID auf ihre gültige); die App wendet sie noch nicht an (Schritt 3) |
| `optional` im Manifest | ja — `--no-enrich` überspringt optionale Quellen samt Abhängigen (heute `inaturalist`), außerdem Stage 01b |
| iNaturalist-Zuordnung | ja — Quelle `inaturalist` mit `sources`-Eintrag; schreibt `entity_external_ids`, bei höheren Taxa unter Namensschlüsseln (`genus:barbus`), die die App abfragt. Mehrere gleichnamige Zeilen einer Rangtabelle teilen diesen Schlüssel und verhindern die Zuordnung deshalb nicht |

---

## Umsetzung

### Übergang: nur Beiträge

Bis die App Aliase anwendet (Schritt 3), dürfen weitere Quellen **nur Beiträge zu
vorhandenen Entitäten** liefern und keine Entitäten anlegen. Fehlt eine
Entität, gilt die Regel aus
[Fehlende und mehrdeutige Zuordnungen](#fehlende-und-mehrdeutige-zuordnungen).

### Schritte

1. *(umgesetzt)* **`depends_on_sources` und Sortierung** in `build.sh`, dazu
   `optional` und `placement_priority` mit eigenen Werten für FishBase und
   SeaLifeBase.
   Erster Anwendungsfall: die kuratierten Klassennamen als eigene Quelle mit
   `depends_on_sources: [fishbase]` (#298), die nur Beiträge liefert.
2. *(umgesetzt)* **Abgleich in `core/`**, über Kandidaten aus
   `species_scientific_names`, dazu der Build-Bericht.
3. **Register und Aliase** — *(im ETL umgesetzt)* Register, Aliase und
   Lebenszyklus in der Identitäts-Stage. Offen: das Umschreiben in der App und
   die neue Schemaversion.
4. *(im ETL umgesetzt)* **Umstellung aller IDs** auf das Format ohne Quelle:
   Der erste Build gegen ein Release ohne Register leitet es ab, und jede
   bisherige ID wird ein Alias auf ihre neue. Das Release erprobt den
   Alias-Mechanismus einmal vollständig, bevor er für einzelne Doppel gebraucht
   wird.
5. **Danach** dürfen Quellen Entitäten anlegen.

Ein Release nach diesem Stand wird mit `publish_release.sh --schema-version 2`
veröffentlicht und braucht eine App, die Aliase anwendet
(`supportedSchemaVersion` 2). Eine ältere App lehnt es dann ab, statt mit
unbekannten IDs ihre Lernstände zu verlieren.

### Bekannte Grenzen

- **Höhere Taxa werden quellenübergreifend nicht zusammengeführt.**
  Gleichnamige Gattungen, Familien, Ordnungen und Klassen zweier Quellen
  bleiben eigene Entitäten. Der Name allein trennt Homonyme nicht: Zwischen
  FishBase und SeaLifeBase gibt es 97 gleichnamige Gattungen und eine
  gleichnamige Familie (*Chilodontidae*), und keine davon gehört zur selben
  Familie oder Klasse (*Acanthus* ist bei FishBase ein Doktorfisch, bei
  SeaLifeBase eine Pflanze). Eine Regel dafür braucht mehr als den Namen,
  etwa die Elternkette oder eine gemeinsame externe ID.
- **Arten, die schon getrennte Entitäten sind, werden nicht zusammengeführt.**
  Der Abgleich läuft nur für Arten mit unbekanntem Schlüssel. Zwei Einträge,
  die sich erst später als dieselbe Art erweisen, bleiben getrennt, bis ein
  eigener Schritt eine davon zum Alias macht.

Unabhängig davon, *(umgesetzt)*: Die iNaturalist-Zuordnung ist eine Quelle
mit `depends_on_sources: [fishbase, sealifebase]` und `optional: true`.

---

## Beispiele

| Quelle | Liefert | Legt Arten an |
|---|---|---|
| Kuratierte Klassennamen | Namen de/fr/es für FishBase-Klassen ohne iNaturalist-Gegenstück | nein |
| iNaturalist | externe IDs | nein |
| WoRMS | AphiaID, Lebensraum-Flags, gültiger Name | nein |
| Crab Database | englische Namen, Synonyme, Fotos; Krabbenarten, die SeaLifeBase fehlen | ja — erst nach Schritt 5; dazu fehlt heute die Lizenz („All rights reserved“) |
