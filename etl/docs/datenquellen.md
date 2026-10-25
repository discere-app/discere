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
- Die Quellen laufen in **zwei Gruppen**, getrennt durch die
  [Identitäts-Stage](#das-register-vergibt-ids-stabil): zuerst die Quellen,
  die Entitäten liefern — erkennbar an ihrer `placement_priority` —, danach
  alle, die nur Beiträge liefern, jede Gruppe für sich nach den
  Abhängigkeiten geordnet. Die zweite Gruppe hängt ihre Beiträge so an
  Entitäten mit endgültigen IDs, und eine Art, die zwei Quellen liefern, ist
  für sie schon eine einzige: Liefe etwa der iNaturalist-Abgleich vorher,
  träfe er beide Zeilen und ordnete die Art als mehrdeutig keiner ID zu. Eine
  Quelle der ersten Gruppe, die von einer der zweiten abhängt, ist ein
  Konfigurationsfehler und bricht ab.
- Ergänzende Quellen adressieren Entitäten über das ID-Register
  (`entity_source_keys`: Quelle, Typ, Schlüssel), nicht über
  `external_source`/`external_id` der Entitätszeile. Liefern zwei Quellen
  dieselbe Entität, trägt die Zeile nur die Spalten der gewichtigeren, und der
  Schlüssel der anderen fände sie dort nicht mehr.
- Die Reihenfolge regelt nur, *wann* eine Quelle läuft — nicht, wessen Beitrag
  gilt. Wo nur ein Wert gelten kann, entscheidet eine ausdrückliche
  [Rangfolge](#rangfolge).
- Quellen, die nur ergänzen und ohne die ein Build trotzdem eine brauchbare
  Referenz-DB ergibt, sagen das im Manifest (`optional: true`, sonst
  `false`). `--no-enrich` überspringt nur diese — und mit ihnen jede Quelle,
  die von einer übersprungenen abhängt —, nicht alle ergänzenden Quellen. Das
  Merkmal fragt bewusst nicht, ob eine Quelle Netzwerk braucht: FishBase und
  SeaLifeBase laden zur Build-Zeit ebenfalls herunter, sind aber die
  Grundlage jedes Builds und dürfen nicht entfallen. Eine Quelle, die
  Entitäten liefert (`placement_priority`), ist deshalb nie optional;
  `core/validate_plugin.sh` lehnt beides zusammen ab. Ein Build mit
  `--no-enrich` ist für Tests da: Ihm fehlen iNaturalist-IDs und
  Ortszuordnungen. Die Validierung prüft deren Mindestzahlen dann nicht
  (`etl/README.md`, Validierung), der Build wird aber kein Release.

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

### Wissenschaftliche Namen

Eine Quelle schreibt je Art und normalisiertem Namen genau eine Zeile in
`species_scientific_names` (Schlüssel `species_id`, `normalized_name`,
`source`). FishBase und SeaLifeBase führen den Namen einer Art oft zusätzlich
unter ihren Synonymen, als `synonym`, `ambiguous synonym` oder `misapplied
name`, und manche Synonyme mehrfach. Der Export ihrer Plugins
(`plugins/*/sql/export.sql`) wählt deshalb fest:

1. der kanonische Name der Art (aus `species`, `is_preferred = 1`, Status
   `valid`) vor jedem gleichnamigen Synonym;
2. unter gleichnamigen Synonymen der Status, der den Namen am deutlichsten
   der Art zuschreibt: `synonym`, dann `ambiguous synonym`, dann `misapplied
   name` — ein falsch angewandter Name ist für Abgleich und Nachfolger kein
   Kandidat und soll einen echten Synonymeintrag nicht verdrängen;
3. danach `source_ref` und die übrigen Spalten, damit jeder Build dieselbe
   Zeile wählt.

Der Import schreibt ohne `OR REPLACE`: Eine doppelte Zeile wäre ein Fehler im
Export und bricht den Build ab. Jede aktive Art mit Gattung hat so genau einen
bevorzugten Namen je Quelle, und er ist ihr eigener (Gattung und Epitheton);
die Validierung prüft beides (`etl/README.md`, Validierung). Eine
SeaLifeBase-Art ohne Gattung trägt den Namen, den die Quelle ihr gibt (siehe
[Gattung und Familie einer Art widersprechen sich](#gattung-und-familie-einer-art-widersprechen-sich));
gegen eine Gattung prüfen lässt er sich nicht.

In `species_scientific_names` kommen nur Synonyme der Ebene `Species`
(`TaxonLevel`). Derselbe Name kann in der Quelle aber bei einer zweiten Art
auf einer anderen Ebene stehen (SeaLifeBase v26.06: *Aphroceras
primigenium*, *Dyssycus primigenius*, *Lipostomella primigenia*). Ob ein Name
mehrdeutig ist, zählt der Export deshalb über alle Ebenen: Jeder Name, den die
Quelle als Synonym mehr als einer ihrer Arten führt — als Binom, ohne
angenommene und falsch angewandte Namen —, steht in
`ambiguous_scientific_names`.

Die App löst Namen über `species_name_lookup` auf (Import, Online-Decks).
Dort steht ein Name nur, wenn er genau eine aktive Art meint
(`core/sql/rebuild_lookup.sql`): die einzige, bei der er bevorzugt ist, oder,
bevorzugt nirgends und in keiner Quelle mehrdeutig
(`ambiguous_scientific_names`), die einzige, die ihn führt; falsch
angewandte Namen zählen nicht. Einen Namen mehrerer Arten — Synonym zweier Arten oder bei
zweien bevorzugt — löst sie nicht auf, statt eine zu raten. Der Build-Bericht
nennt jeden solchen Namen mit allen Arten (Quelle `lookup`, Kategorie
`ambiguous`) und jeden, den aktive Arten nur als falsch angewandten führen
(`misapplied`).

### Platzhalter der Quellen

Ein Datensatz, den eine Quelle nur als Platzhalter führt, ist keine Entität
und wird nicht importiert, samt allen Beiträgen dazu. Sonst wäre er in der
App such- und lernbar, ein Name ohne eigene Art träfe ihn im Abgleich, und
als [Nachfolger](#nachfolger) einer verschwundenen Art zöge er deren
Lernstände auf sich. Das Plugin der Quelle schließt ihn aus, bevor es
Entitäten schreibt; der Abgleich und die Identitäts-Stage kennen keine
Sonderregel.

Heute betrifft das FishBase (`plugins/fishbase/sql/export.sql`): die
Gattung GenCode 0 mit den Arten SpecCode 0 und 1, an denen FishBase rund 160
Synonyme ohne eigene Art aufhängt, und die Familie FamCode 0, die nur diese
Gattung hält. Ihre Namen wechseln mit der FishBase-Version — v25.04:
Gattung „Genus“, Arten *Genus Species* und *Genus Sp*, keine Familie 0;
v26.06: Familie „Family“, Gattung „To“, Arten *To be entered* und *To Sp* —,
die Codes bleiben.

Bei SeaLifeBase (`plugins/sealifebase/sql/export.sql`) ist es die Art
*DummyGenus DummySpecies* (v26.06: SpecCode 174673), ohne Gattung, Familie
und Beiträge. Einen eigenen Code hat sie nicht; erkannt wird sie am Namen.

Führt der Vorgänger sie noch als Entitäten (refdb-v2 tut das), übernimmt der
erste Build ohne sie sie wie jede Entität ohne aktiven Schlüssel aus dem
Vorgänger: die Arten als deprecated, samt ihren Namen. Diese Namen sind dann
Namen veralteter Arten und für den Abgleich und die Nachfolger kein
Kandidat; ihr eigener Name (*To be entered*) trifft keine aktive Art, einen
Nachfolger bekommen sie also nicht. Lernstände, die auf sie zeigen, bleiben
dort. *DummyGenus DummySpecies* war in refdb-v2 aktiv und ist seither eine
veraltete Art ohne Gattung.

### Fehlende Codes in der Quelle

SeaLifeBase nennt bei einigen Arten keinen GenCode (v26.06: 154), wohl aber
den Gattungsnamen in der Spalte `Genus`. Der Export ordnet eine solche Art
der SeaLifeBase-Gattung dieses Namens zu, wenn genau eine davon zur Art
passt (siehe
[Gattung und Familie einer Art widersprechen sich](#gattung-und-familie-einer-art-widersprechen-sich)).
Gattungsnamen sind in SeaLifeBase nicht eindeutig (v26.06: 87 doppelte); ein
Name, unter dem mehrere passende Gattungen stehen, und ein unbekannter Name
ordnen nichts zu, die Gattung bleibt leer. Der Build-Bericht nennt jede Art,
deren Gattung über den Namen kam (`genus_by_name`), und jede, die offen
blieb (`genus_unresolved`, mit Grund). Für höhere Ränge gibt es keine solche
Regel: Fehlt einer Gattung die Familie oder einer Familie die Ordnung, nennt
die Quelle keinen Namen, über den sie sich auflösen ließe (siehe [Bekannte Grenzen](#bekannte-grenzen)).

### Doppelte Codes in der Quelle

Der Code einer Zeile (ClassNum, Ordnum, FamCode, GenCode, SpecCode) ist ihr
Quellenschlüssel. SeaLifeBase vergibt drei Ordnum doppelt (v26.06): 10385
an *Phymosomatoida* (Echinoidea) und „Not assigned“ (Chromista), 10670 an
*Globigerinida* (Foraminifera) und *Tetractinellida* (Porifera), 10688 an
*Araneae* (Arachnida) und *Seguenziida* (Gastropoda). FishBase führt keinen
doppelten Code, auf keinem Rang. Ein doppelter Code nennt kein Taxon: Eine
zufällig gewählte Zeile hinge Familien unter eine Ordnung aus einem anderen
Stamm, und ihr Schlüssel könnte von Build zu Build das Taxon wechseln. Beide
Exporte wenden deshalb dieselbe Regel an (`core/sql/source_codes.sql`):

- **Ordnung einer Familie.** Bei eindeutigem Ordnum die Ordnung dieses
  Codes. Bei doppeltem die Zeile, deren Name gleich dem Ordnungsnamen ist,
  den die Familie selbst nennt (ohne Leerzeichen am Rand und Groß- und
  Kleinschreibung), und deren ClassNum gleich der ClassNum der Familie ist.
  Trifft das nicht genau eine Zeile, hat die Familie keine Ordnung.
- **Entität unter einem doppelten Ordnum** wird höchstens eine Zeile: die
  einzige, an deren Familien Arten hängen, über den FamCode der Art oder
  über ihre Gattung —, und nur, wenn sie kein Rang-Platzhalter ist (Muster
  aus `core/data/placeholder_patterns.csv`): Zwei gleichnamige Platzhalter
  verschiedener Klassen könnten den Schlüssel sonst tauschen, ohne dass sich
  ein Name ändert. Halten keine oder mehrere Zeilen Arten oder nur ein
  Platzhalter, wird keine exportiert. Die übrigen Zeilen bekommen keinen
  eigenen Schlüssel, denn
  der Code nennt schon das Taxon, das Arten hält; ihre Familien bleiben
  ohne Ordnung.
- **Übrige Ränge.** Für einen doppelten ClassNum, FamCode, GenCode oder
  SpecCode nennt die Quelle keinen Namen, über den sich eine Zeile wählen
  ließe. Keine wird exportiert; was auf den Code zeigt, bleibt ohne diese
  Stufe.

Jede Zeile eines doppelten Codes steht im Build-Bericht (`code_duplicate`,
mit Ausgang), ebenso jede Familie unter einem doppelten Ordnum
(`family_order_resolved` mit ihrer Ordnung, `family_order_rejected` mit
Grund). Für v26.06:

| Ordnum | Entität | Familien |
|---|---|---|
| 10670 | *Tetractinellida* | alle 8 nennen *Tetractinellida*; *Globigerinida* hat keine Familie |
| 10688 | *Seguenziida* | 8 nennen *Seguenziida*; *Desidae* (Spinnen, ohne Arten) nennt *Araneae* und bleibt ohne Ordnung |
| 10385 | keine | die Chromista-Familie „Not assigned“ (FamCode 4430, ohne Arten) nennt „Not assigned“ und bleibt ohne Ordnung; *Phymosomatoida* hat keine Familie |

Unter 10385 hält keine Zeile Arten, also wird keine exportiert. Der
Schlüssel bleibt inaktiv auf *Phymosomatoida*, das der Vorgänger dort führt,
und die Identitäts-Stage übernimmt die Ordnung wie jede Entität ohne aktiven
Schlüssel, nun ohne Familie. „Not assigned“ unter diesen Schlüssel zu legen
hieße, ihn auf ein anderes Taxon zu legen.

Dass der Schlüssel einer gewählten Zeile dasselbe Taxon nennt wie im
Vorgänger, kann der Export nicht wissen; er kennt den Vorgänger nicht. Das
prüft die Identitäts-Stage für jeden bekannten Schlüssel eines höheren
Taxons (siehe [Das Register vergibt IDs stabil](#das-register-vergibt-ids-stabil)).

Weil jeder Code nur einmal exportiert wird, steht jede Klasse, Ordnung,
Familie, Gattung und Art genau einmal im Export. Klassen, Ordnungen und
Familien importieren die Plugins ohne `OR IGNORE`; eine Kollision bricht den
Import ab, statt still eine Zeile zu behalten.

### Stamm einer Familie gegen ihren Ordnungscode

Eine SeaLifeBase-Familie nennt ihren Stamm selbst (`families.Phylum`); die
DB zeigt die Kette über ihren Ordnungscode: Familie → Ordnung → Klasse →
Stamm. Bei 69 Familien mit eindeutigem Ordnum (v26.06) nennen beide einen
anderen Stamm. Meist ist es derselbe Stamm unter anderem Namen, bei 11 ein
echter Widerspruch: *Priapulidae* nennt Priapulida, ihr Code zeigt auf
Cocculiniformia (Gastropoda), und *Priapulus caudatus* stünde unter den
Schnecken. Der Ordnungscode liegt dort um eins neben dem richtigen (10652
statt 10653). FishBase führt keinen Stamm an der Familie. Der Export prüft
deshalb, nach der Auflösung doppelter Codes
(`plugins/sealifebase/sql/export.sql`):

1. **Derselbe Stamm** — gleich (ohne Leerzeichen am Rand und Groß- und
   Kleinschreibung) oder als Paar in
   `plugins/sealifebase/data/family_phylum_equivalents.csv` (Stamm der
   Familie, Stamm der Kette, Begründung): Die Ordnung bleibt.
2. **Widerspruch** — Die Familie bekommt die Ordnungszeile, deren Name
   gleich dem Ordnungsnamen ist, den sie selbst nennt, und deren ClassNum
   gleich ihrer eigenen ist, wenn es genau eine gibt, sie exportiert wird
   und ihr Stamm nach 1. zu dem der Familie passt — außer die Familie ist
   selbst ein Rang-Platzhalter („Not assigned“). Sonst hat die Familie
   keine Ordnung. Einen Platzhalter hängt die Regel nie um: Gleichnamige
   Platzhalter unterscheidet die Identitäts-Stage nur am Elternschlüssel,
   und diese Prüfung entfällt für eine umgehängte Familie (siehe unten).
3. **Nicht vergleichbar** — Fehlt ein Stamm oder ist einer ein
   Rang-Platzhalter („Not Assigned (Plantae)“, Muster aus
   `core/data/placeholder_patterns.csv`), bleibt die Ordnung. Ein
   Platzhalter nennt keinen Stamm, der gleich oder verschieden sein könnte.

Die Liste gleichwertiger Namen enthält nur Paare, die in v26.06 vorkommen
und dieselbe Gruppe meinen oder eine in der anderen enthalten:

| Stamm der Familie | Stamm der Kette | Familien | Grund |
|---|---|---|---|
| Dinophyta | Myzozoa | 41 | Dinoflagellaten, Teil der Myzozoa |
| Platyhelminthes | Xenacoelomorpha | 15 | 14 Acoela, früher unter den Plattwürmern, und *Ectocotylidae* (Ausnahme, unten) |
| Chorophyta | Chlorophyta | 1 | Schreibfehler |
| Ochrophyta | Bacillariophyta | 1 | Kieselalgen, Teil der Ochrophyta |

Jedes Paar steht in der Richtung, in der es vorkommt. Bei allen 58 Familien
nennen sie und ihr Code außerdem denselben Ordnungsnamen. Ein Paar sagt nur,
dass die beiden Namen vergleichbar sind, nicht, dass jede Familie darunter
richtig hängt: *Ectocotylidae* ist eine Plattwurm-Familie (WoRMS:
*Ectocotyla* unter Proseriata), nennt aber selbst die Ordnung Acoela und
besteht deshalb jede Regel aus der Quelle. Für solche Fälle gibt es eine
kuratierte Ausnahmeliste,
`plugins/sealifebase/data/family_order_exceptions.csv` (FamCode, Name,
Grund, Beleg): Eine Familie darin hat keine Ordnung, was immer die Regel
ergäbe. Jeder Eintrag muss FamCode und Namen einer Familie mit Ordnung
treffen, sonst bricht der Export ab, wie bei jeder eigenen Datei. Die
übrigen 57 Familien der Liste stimmen mit WoRMS überein, über die Familie
oder ihre Gattungen. Die Liste ist
eine eigene, nicht die gleichwertigen Stämme der iNaturalist-Zuordnung
(`plugins/inaturalist/data/phylum_equivalents.csv`): Jene übersetzt
SeaLifeBase-Namen der Kette in iNaturalist-Namen (Myzozoa → Miozoa), diese
Namen innerhalb von SeaLifeBase (Dinophyta → Myzozoa), und ein
zusammengelegtes Paar wie der Schreibfehler „Chorophyta“ hätte in der
anderen Prüfung nichts zu suchen.

Ergebnis für v26.06:

| Familie | nennt | Code zeigt auf | Ergebnis |
|---|---|---|---|
| *Priapulidae*, *Tubiluchidae* | Priapulida | Cocculiniformia / Gastropoda | Not assigned / Priapulomorpha / Priapulida |
| *Phoronidae*, *Actinotrochidae* | Phoronida | Not assigned / Aplacophora | Not assigned / Not assigned / Phoronida |
| *Xenoturbellidae* | Xenacoelomorpha | Not assigned / Aplacophora | Not assigned / Not assigned / Xenacoelomorpha |
| *Palaeotropidae* | Echinodermata | Not assigned / Aplacophora | Spatangoida / Echinoidea / Echinodermata |
| *Maccabeidae* | Priapulida | Didelphimorphia / Mammalia | keine Ordnung: keine Zeile „Not assigned“ in ihrer Klasse |
| *Psamminidae*, *Stannomidae*, *Syringamminidae*, „Not assigned“ | Foraminifera | Lepetellida / Gastropoda | keine Ordnung: keine Zeile „Not assigned“ in ihrer Klasse |
| *Ectocotylidae* | Platyhelminthes | Acoela / Not assigned / Xenacoelomorpha | keine Ordnung: Ausnahme |

Nicht vergleichbar sind fünf Familien, deren Stamm auf beiden Seiten ein
Platzhalter ist (*Jakobaceae*, *Trochosiraceae* und drei „Not assigned“).

**Klasse.** Bei 329 Familien mit eindeutigem Ordnum weicht auch die eigene
ClassNum von der Klasse der Ordnung ab, bei 302 davon im selben Stamm.
Fast alle sind ältere oder andere Namen derselben Gruppe (Copepoda und
Thecostraca gegen Hexanauplia, Articulata gegen Rhynchonellata, Staurozoa
gegen Scyphozoa, Umstellungen innerhalb der Foraminiferen) oder eine
Platzhalter-Klasse auf einer Seite (Reptilia, Turbellaria). Der einzige
Fall, der wie ein Widerspruch aussieht, *Margaritidae* (FamCode 5025,
ClassNum der Gastropoda, Ordnung Ostreida der Muscheln), ist ein Fehler der
ClassNum: Die Familie hält die Perlmuscheln *Pinctada*, und ihr eigenes Feld
`Class` nennt Bivalvia. Eine Regel über die ClassNum der Familie hinge sie
falsch um. Für die Klasse gibt es deshalb keine eigene Prüfung; sie zählt nur
als Teil der Suche in 2.

Jeder Fall nach 2. und 3. und jede Ausnahme steht im Build-Bericht:
`family_phylum_resolved` mit der neuen Ordnung, `family_phylum_rejected`
mit Grund, `family_phylum_unclear`, `family_order_exception` mit dem Grund
aus der Liste, je mit der Kette über den Code.

Eine Familie nach 2. hängt unter einem anderen Elternschlüssel, als ihr
Code nennt, und meist auch als im Vorgänger. Das allein würde die
Identitäts-Stage abbrechen lassen (siehe [Das Register vergibt IDs
stabil](#das-register-vergibt-ids-stabil)). Der Export schreibt jede solche
Familie mit ihrem neuen Elternschlüssel in `source_parent_overrides`, und die
Stage lässt genau diesen Wechsel zu: Der Name der Familie und damit das
Taxon hinter ihrem Schlüssel bleiben, nur die Einordnung wird berichtigt.
Jeder andere Wechsel bricht weiter ab, und `validate.sql` prüft, dass jede
Familie der Tabelle in der DB unter der genannten Ordnung hängt. Eine
Familie ohne Ordnung braucht keinen Eintrag: Eine fehlende Elternstufe ist
kein Wechsel.

### Mehrere Verbreitungszeilen einer Art und Region

Die Verbreitung (`country`, `countrysub`) führt für eine Art in einem Land
bzw. einer Teilregion teils mehrere Zeilen, meist für verschiedene
Populationen oder Unterarten. *Oreochromis niloticus* (FishBase 2) steht in
Kenia fünfmal: `native` im Turkana-Becken (zweimal), `introduced` im
Viktoriasee, `endemic` als Unterart im Baringo-See und im Suguta. Die DB hält
je Art und Region eine Zeile (`taxonomy_distribution_regions`), und die App
zeigt sie als Aussage über die Art: Mit `native` oder `endemic` gilt das
Land als heimisch. Beide Exporte fassen die Zeilen deshalb nach derselben
Regel zusammen (`core/sql/distribution_regions.sql`), den Status verglichen
ohne Groß- und Kleinschreibung:

1. **native**, sobald eine Zeile `native` sagt.
2. **endemic** nur, wenn alle Zeilen `endemic` sagen. Endemisch im Land ist
   die Art nicht, wenn es nur eine ihrer Unterarten ist; neben `native`
   gilt `native`.
3. **introduced**, wenn keine Zeile `native` oder `endemic` sagt.
4. **Sonst** der erste Status der Rangfolge `questionable`, `error`,
   `misidentification`, `extirpated`, `stray`, `not established`,
   `reintroduced`, `established`, ohne Status. Vorn steht, was weniger über
   die Präsenz der Art behauptet: ein Zweifel, dann ein als falsch erkannter
   Nachweis, dann eine frühere Präsenz, dann eine gelegentliche oder
   gescheiterte eingeführte, zuletzt eine dauerhafte. Ohne Status steht
   hinten, weil die App eine Region ohne Status als heimisch zeigt.

`endemic` neben einem anderen Status als `native` (etwa `endemic` und
`introduced`) sowie ein Status außerhalb dieser Liste brechen den Export ab,
sobald sie in einem Schlüssel mit mehreren Zeilen stehen: Keine Regel sagt,
was dann für die Art gilt. In v26.06 kommt beides nicht vor.

Präsenz, threatened, Häufigkeit, Bedeutung und Kommentar behalten ihren
Wert nur, wenn alle Zeilen des Schlüssels ihn teilen; sonst bleiben sie
leer, und ein leerer Wert zählt dabei als eigener Wert. Was nur ein Teil der
Zeilen sagt, gilt nicht für die Art als Ganzes, auch nicht, wenn es die
Mehrheit ist: *Salmo trutta* steht in der Schweiz als `native` ohne Präsenz,
weil eine zweite Zeile sie dort als ausgestorben führt („Considered locally
extinct in 1990“), und *Cobitis minamorii* in Japan
ohne threatened, obwohl drei von vier Zeilen „Endangered“ sagen. Der
Kommentar folgt derselben Regel: Er beschreibt eine Population, und die App
zeigt ihn nicht. Unterscheiden sich Zeilen gleichen Rangs nur in der
Schreibweise des Status, gilt die erste in Sortierung („Native“ vor
„native“). Das Ergebnis hängt so nicht von der Reihenfolge der Eingabe ab,
und die Plugins importieren die Verbreitung ohne `OR IGNORE`: Eine Kollision
bricht den Import ab.

Ist das Ergebnis mehrerer Zeilen `introduced` und sagt eine von ihnen
`not established` oder Präsenz `absent`, entsteht für den Schlüssel keine
Zeile. Ob die Einführung gelang, bleibt offen; eine Zeile mit leerer Präsenz
läse die App als vorkommend, eine ohne Status als heimisch. *Salmo trutta*
in Nepal (`introduced`/`present` neben `not established`/`absent`,
„Introduction was unsuccessful“) fehlt deshalb. Bei `native` gilt das nicht:
Dort betrifft ein ausgestorbener oder fehlender Bestand eine Population,
nicht die Heimat der Art.

Jeder Schlüssel mit mehreren Zeilen steht im Build-Bericht, mit dem Status
seiner Zeilen, dem Ergebnis und den Spalten, die wegen Widerspruchs leer
bleiben, oder mit „ausgelassen: Einführung widersprüchlich“:
`distribution_status_merged` bei verschiedenem Status, sonst
`distribution_rows_merged`. In v26.06:

| Status der Zeilen | FishBase | SeaLifeBase | Ergebnis |
|---|---|---|---|
| endemic, native | 19 | – | native |
| introduced, native | 7 | 1 | native |
| native, questionable | 4 | 1 | native |
| extirpated, native | 2 | – | native |
| endemic, introduced, native | 1 | – | native |
| introduced, not established | 1 | – | ausgelassen |
| native, stray | – | 1 | native |
| gleicher Status | 140 | 145 | dieser |

Die Regel sieht die Art als Ganzes und verliert damit, was nur für eine
Population gilt. Die App liest eine leere Präsenz wie jede andere außer
`absent` als vorkommend (Regionsfilter, Häufigkeit) und einen leeren
threatened-Wert als nicht bedroht. *Salmo trutta* zählt damit in der
Schweiz weiter als heimisch und vorkommend.

### Mehrere Zeilen eines Volksnamens

`comnames` führt einen Namen einer Art in derselben Sprache und demselben
Land teils mehrmals, mit anderem Rang, anderem Vorzug (`PreferredName`) oder
anderem Namenstyp (FAO neben Vernacular). Die DB hält je Entität, Name,
Sprache, Quelle und Land eine Zeile (Index `idx_common_names_key` auf
`common_names`). Ohne Land (C_Code 9999, global) zählt dabei als ein
eigenes Land: Der Index vergleicht `IFNULL(country, '')`, weil ein UNIQUE
zwei NULL nie gleich setzt.

Beide Exporte wählen je Schlüssel dieselbe Zeile
(`core/sql/common_names.sql`): die bevorzugte vor den übrigen, dann die mit
dem niedrigsten Rang (ohne Rang zuerst), dann nach Namenstyp (ohne
zuletzt) und `entity_type`. Vorzug vor Rang und ohne Rang zuerst, weil die
App die Zeilen eines Namens in dieser Folge liest (SQLite sortiert NULL vor
jeden Wert): Bleibt genau die Zeile, die sie unter allen
zuerst gelesen hätte, zeigt sie dasselbe, als stünden alle da. Höchster
Vorzug und niedrigster Rang aus verschiedenen Zeilen zusammengesetzt
verschöben dagegen die Sortierung. Namenstyp und `entity_type` liest die
App nicht; sie machen das Ergebnis unabhängig von der Reihenfolge der
Eingabe. Die Plugins importieren ohne `OR IGNORE`: Eine Kollision ist ein
Fehler im Export und bricht den Import ab.

Die Volksnamen übernommener Entitäten (siehe [Lebenszyklus](#lebenszyklus))
wählt die Identitäts-Stage nach derselben Regel (`carried_common_names_sql`
in `core/identity.sh`): Ein Vorgänger kann mehrere Zeilen eines Schlüssels
führen, und korrigieren lässt er sich so wenig wie eine Quelle. Die Zahl der dabei
zusammengefassten Schlüssel steht im Log der Stage.

In v26.06 fasst FishBase 1.814 Schlüssel zusammen (72 ohne Land),
SeaLifeBase 4.067 (103 ohne Land). Bei 24 Schlüsseln von FishBase steht die
bevorzugte Zeile nicht auf dem niedrigsten Rang; bei 38 von FishBase und 9
von SeaLifeBase entscheidet erst der Namenstyp. Die Zahlen stehen je Plugin
im Log („Volksnamen zusammengefasst: …“), nicht im Build-Bericht: Einzeln
aufgeführt wären einige tausend Schlüssel kein Signal.

### Gattung und Familie einer Art widersprechen sich

Eine SeaLifeBase-Art nennt ihre Familie zweimal: über die Gattung (GenCode)
und selbst (FamCode). In v26.06 widersprechen sich beide bei 854 Arten,
teils bis hinauf zum Stamm (Hydrozoen der Gattung *Gattya* hängen an einer
gleichnamigen Rotalgen-Gattung). Welche Angabe stimmt, sagt die Quelle
nicht. Der Export behält die Gattung — über GenCode oder über den Namen
gefunden — nur, wenn sie zur Art passt, und vergleicht dazu die Kette, die
die DB zeigt: Familie → Ordnung → Klasse → Stamm, mit der Ordnung nach
[Doppelte Codes in der Quelle](#doppelte-codes-in-der-quelle) und
[Stamm einer Familie gegen ihren Ordnungscode](#stamm-einer-familie-gegen-ihren-ordnungscode).
Die eigenen Felder `ClassNum` und `Phylum` der Familien zählen sonst nicht;
sie widersprechen der Kette bei Hunderten Familien, meist mit einem anderen
Namen derselben Gruppe.

- **Gleiche Familie und gleicher Name** (Gattungsname gleich `Genus` der
  Art, ohne Rücksicht auf Leerzeichen und Groß- und Kleinschreibung): Die
  Gattung bleibt.
- **Anderer Name, anderer Stamm, andere Klasse, oder die Ordnung einer Seite
  ist unklar** (Familie ohne Ordnung, auch unter einem doppelten Ordnum,
  der sich nicht auflösen lässt, Gattung ohne
  Familie, Klasse oder Stamm ein Rang-Platzhalter wie „Not assigned“ —
  zwei Familien unter derselben Platzhalter-Klasse können in verschiedenen
  echten Klassen stehen): Die Gattung bleibt leer (`genus_rejected`, Grund
  `Name`, `Stamm`, `Klasse` bzw. `Ordnung unklar`; v26.06: 41 Arten), außer
  eine gleichnamige Gattung passt (unten). Lieber
  keine Einordnung als eine falsche, auch wenn im Einzelfall die Gattung
  recht hätte und der FamCode der Art falsch ist. Platzhalter erkennt der
  Export nach denselben Mustern wie Stage 02d
  (`core/data/placeholder_patterns.csv`).
- **Nur Familie oder Ordnung anders, Klasse und Stamm gleich:** Die Gattung
  bleibt (`genus_kept_family_differs`, `genus_kept_order_differs`, mit
  beiden Ketten; v26.06: 639 bzw. 165). Meist ist eine der beiden Angaben
  nach einer Umstellung veraltet.

Passt die Gattung des GenCode nicht, prüft der Export nach derselben Regel
jede andere Gattung, die den Namen aus `Genus` der Art trägt. Passt genau
eine, gilt sie (`genus_replaced_by_name`, mit beiden Gattungen und ihren
Ketten; v26.06: 10 Arten). So kommen die Hydrozoen der Gattung *Halopteris*,
deren GenCode auf eine gleichnamige Braunalgen-Gattung zeigt, zur
Hydrozoen-Gattung *Halopteris*, und *Stephanomia amphytridis*, deren GenCode
auf *Halistemma* zeigt, zur Gattung *Stephanomia*. Passt die Gattung des
GenCode, gilt sie, auch wenn eine gleichnamige ebenfalls passt. Passen
mehrere gleichnamige oder keine, bleibt die Gattung leer; der Bericht nennt
dann, wie viele es gibt und wie viele davon passen.

Eine Art ohne Gattung behält ihren wissenschaftlichen Namen: Bevorzugt ist
der Name, den die Quelle ihr in den Spalten `Genus` und `Species` gibt, auch
wenn ihr GenCode auf eine anders benannte Gattung zeigt. Er ordnet sie
keiner Gattung zu, und über ihn findet sie `species_name_lookup` und der
iNaturalist-Abgleich. `species.name` bleibt das Epitheton. Die App zeigt
und sucht die Art unter diesem bevorzugten Namen (*Gattya humilis*, nicht
„humilis“) und die Ränge über ihr als „nicht zugeordnet“.

Eine Invariante in `validate.sql` für die Gattung gibt es nicht: Die DB
kennt den FamCode der Art nicht, nur die Kette über ihre Gattung. Die
Prüfung sitzt im Export, der Build-Bericht hält jeden Fall fest. Die
Validierung prüft nur, dass der bevorzugte Name einer Art ohne Gattung auf
ihr Epitheton endet.

### Stamm und Kette bei der iNaturalist-Zuordnung

Der Abgleich über den Namen trennt keine Homonyme: Die Schnecke *Triphora
pusilla* trägt denselben Namen wie eine Orchidee, die Flohkrebs-Gattung
*Tara* denselben wie eine Springspinne, die Rochengattung *Batis* denselben
wie eine Vogelgattung. Kennt iNaturalist nur das fremde Taxon, träfe der
Name es eindeutig. Das Plugin `inaturalist` vergleicht deshalb vor dem
Abgleich jedes iNaturalist-Taxon mit der eigenen Kette
(`plugins/inaturalist/sql/export.sql`):

- **iNaturalist-Seite** — Stamm, Klasse, Ordnung und Familie aus der
  Ahnenkette in `taxa.csv` (Spalte `ancestry`), über die eigenen Zeilen der
  Datei, ohne API.
- **Eigene Kette** — Art › Gattung › Familie › Ordnung › Klasse, der Stamm
  in `super_class` (`plugins/inaturalist/sql/reference_names.sql`). FishBase
  führt in dieser Spalte die Überklasse (Osteichthyes, Agnatha, …); ihre
  Taxa gelten als Chordata.

Ein iNaturalist-Taxon geht nur in den Abgleich, wenn es zu **jeder** Entität
passt, die seinen Namen auf diesem Rang trägt — bei Arten auch als Synonym
(ohne falsch angewandte Namen, wie im Abgleich). Für höhere Taxa heißt das:
Der Namensschlüssel (`genus:megalomma`) steht für alle gleichnamigen Zeilen
der Rangtabelle, an denen eine Art hängt — aktiv oder veraltet, denn auch
veraltete Arten stehen in Decks; bei Familien und Ordnungen eine Art
darunter. Eine Zeile ohne jede Art zeigt die App unter keinem Schlüssel
(Suche und Kinderlisten verlangen eine aktive Art darunter, eine Art zeigt
ihre eigene Kette); FishBase und SeaLifeBase führen so etwa
Synonymgattungen (*Gobio* zusätzlich ohne Familie, *Torpedo* unter
Malapteruridae). Eine solche Zeile verhindert deshalb keine Zuordnung.

1. **Stamm.** Gleich, oder das Paar steht in
   `plugins/inaturalist/data/phylum_equivalents.csv` (Stamm der Kette,
   iNaturalist-Stamm, Begründung): SeaLifeBase und iNaturalist fassen oder
   benennen manche Stämme verschieden (Bacillariophyta → Ochrophyta,
   Kamptozoa → Entoprocta, Myzozoa → Miozoa, …). Nicht prüfbar — und damit
   keine Zuordnung — ist eine Kette ohne Stamm (etwa eine Art ohne
   Gattung), ein Platzhalter-Stamm („Not Assigned (Plantae)“, Muster aus
   `core/data/placeholder_patterns.csv`) und ein iNaturalist-Taxon ohne
   Stamm in seiner Ahnenkette. Das Reich, das ein Platzhalter nennt, taugt
   nicht als Ersatz: SeaLifeBase ordnet darunter Wimpertierchen und
   Kieselalgen den Pflanzen zu, und gleichnamige Korb- und Lippenblütler
   bestünden die Prüfung.
2. **Eine Klasse.** Liegen die Entitäten eines Namens in verschiedenen
   Klassen (Platzhalter zählen nicht), ist jedes iNaturalist-Taxon für eine
   davon falsch: keine Zuordnung, wie bei verschiedenen Stämmen.
3. **Klasse, Ordnung oder Familie.** Bei Gattungen, Familien und Ordnungen
   — und bei Arten, deren Name bei iNaturalist mehrere aktive Taxa trägt,
   also nachweislich anfällig ist — genügt der Stamm nicht: Innerhalb eines
   Stamms wiederholen sich Namen (ein Krebs bei uns, ein Insekt bei
   iNaturalist; ein Fisch, eine Echse). Mindestens einer der Ränge über dem
   eigenen muss zu jeder Entität passen: die Klasse gleich oder gleichwertig
   laut `plugins/inaturalist/data/class_equivalents.csv` (FishBase teilt
   die Strahlenflosser in Unterklassen, iNaturalist führt
   Actinopterygii; SeaLifeBase führt Octocorallia, iNaturalist Anthozoa;
   …), oder die Ordnung bzw. die Familie gleich. Klassen selbst prüft nur
   der Stamm.
4. **Synonym-Treffer bei Arten.** Trifft eine Art nur über ein Synonym,
   muss die Familie des iNaturalist-Taxons gleich der eigenen sein, und das
   Epitheton des Synonyms muss in den ersten vier Buchstaben dem der Art
   gleichen (klein geschrieben, ohne Leerzeichen am Rand;
   `plugins/inaturalist/import.sh`). SeaLifeBase führt Synonyme, die
   anderen Arten gehören — aus anderen Familien (der Kappensäger
   *Lophodytes cucullatus* als Synonym einer Möwe) wie aus derselben
   (*Mactra mera* mit dem Synonym *Mactra antiquata*). Ein echtes Synonym
   behält meist das Epitheton und wechselt nur die Gattung; vier
   Buchstaben lassen Genusangleichungen (*pulcher*/*pulchra*) und die
   häufigen Schreibvarianten durch. Gemessen an den 1.008 Synonym-Treffern
   eines Builds aus v26.06 gegen WoRMS fangen drei, vier und fünf Buchstaben dieselben
   12 von 23 Widersprüchen; vier kosten 52 von WoRMS bestätigte Treffer,
   drei 48 (die vier zusätzlichen sind Schreibvarianten wie
   *leeorum*/*leei*), fünf 60. Vier halbieren gegenüber drei die Rate, mit
   der zwei verschiedene Epitheta derselben Gattung zufällig gleich
   beginnen (0,15 statt 0,33 %).

Beide Listen gleichwertiger Namen enthalten nur Paare, die dieselbe Gruppe
meinen oder eine in der anderen enthalten, und die unter den gleichnamigen
Kandidaten tatsächlich vorkommen. Klassen, die iNaturalist anders aufteilt
als SeaLifeBase (Chlorophyceae, Prasinophyceae, Chrysophyceae), stehen
nicht darin; ihre Gattungen passen nur über Ordnung oder Familie. Ein
Paar macht zwei Namen nur vergleichbar, es schließt keine Homonyme aus:
Gleiche Gattungsnamen kommen in verschiedenen Stämmen und auch innerhalb
eines Stamms vor, zwischen den Nomenklatur-Codes ohnehin, innerhalb eines
Codes als (meist ältere, noch nicht ersetzte) Homonyme.

Führt iNaturalist mehrere aktive Taxa desselben Namens und Rangs, zählen
nur die, die alle Prüfungen bestehen: Bleibt genau eines, geht es in den
Abgleich (die Ruderfußkrebs-Gattung *Gaussia* neben der gleichnamigen
Palme), bleiben mehrere, keines.

Lieber keine Zuordnung als eine falsche — auch dann, wenn im Einzelfall die
eigene Kette falsch ist und iNaturalist recht hätte (das Seegras
*Halophila* steht bei SeaLifeBase unter einer Moostierchen-Familie) oder ein
Synonym nur nach einer Umstellung der Familie anders eingeordnet ist.

Jedes abgelehnte Taxon steht im Build-Bericht mit Grund und den Ketten
beider Seiten: `phylum_mixed` (Stamm passt zu einem Teil der Entitäten),
`phylum_unknown` (nicht prüfbar), `phylum_mismatch` (passt zu keiner),
`class_mixed` (Entitäten in mehreren Klassen), `rank_mismatch` (weder
Klasse noch Ordnung noch Familie passen), `synonym_family` bzw.
`synonym_epithet` (Synonym-Treffer mit anderer Familie bzw. anderem
Epitheton). Die Entitäten dahinter stehen zusätzlich in der DB (siehe
unten).

Jede Zuordnung trägt in `entity_external_ids.metadata_json` Stamm, Klasse,
Ordnung und Familie des iNaturalist-Taxons, `matched_by` (`name` oder
`synonym`) und `homonym`. Nach dem Import prüft das Plugin jede Zuordnung
erneut gegen Kette und Listen
(`plugins/inaturalist/sql/validate_mappings.sql`), mit eigener SQL: Die
iNaturalist-Kette, ob ein Name mehrere Taxa trägt und ob eine Art über ein
Synonym zugeordnet ist, leitet es selbst aus `taxa.csv` und den Namen der
DB ab, und `metadata_json` muss dazu passen. Ein Fehler in der Prüfung oder
der Ableitung des Exports lässt den Build scheitern, statt falsche
Zuordnungen still durchzulassen. Gemeinsam bleiben beiden nur die Kette in
der DB und die Listen gleichwertiger Namen. `validate.sql`
prüft zusätzlich, was ohne iNaturalist feststeht: Jede zugeordnete Art und
jede Entität hinter einem zugeordneten Namensschlüssel hat eine Kette bis
zu einer Klasse mit Stamm. Die App liest `metadata_json` nicht.

Die App sucht für Arten und höhere Taxa ohne Zuordnung zur Laufzeit selbst
bei iNaturalist, über den Namen ([`docs/enrichment.md`](../../docs/enrichment.md#die-inat-taxon-id-einer-art-oder-eines-höheren-rangs)).
Damit sie dabei nicht wiederfindet, was hier abgelehnt wurde, und einen
Treffer ohne Namen und ohne eigene Listen prüfen kann, schreibt das Plugin
zwei Tabellen:

- **`entity_external_id_rejections`** (`entity_id`, `entity_type`,
  `provider`, `reason`) — jede Entität, deren Name ein Taxon trifft, das der
  Abgleich bewusst nicht nimmt, unter dem Schlüssel, den die App abfragt
  (Art-ID bzw. Namensschlüssel). Gründe wie im Build-Bericht:
  die fünf Prüfungen oben, `synonym_family` und `synonym_epithet`, dazu
  `ambiguous` für Homonyme mit mehreren passenden Taxa und für Arten, die
  der Abgleich nicht eindeutig zuordnet. Eine Zeile je Grund. Wer trotzdem
  eine Zuordnung bekommt (über ein anderes Taxon seines Namens), steht dort
  nicht. Die App sucht für diese Entitäten nicht: Ihre Suche prüft nur
  Stamm und Klasse und fände die abgelehnten Taxa wieder.
- **`inat_allowed_ancestors`** (`class_id`, `rank`, `inat_taxon_id`) — je
  eigener Klasse die iNaturalist-IDs der Stämme (`rank = 'phylum'`) und
  Klassen (`'class'`), die zu ihr passen: gleicher Name oder gleichwertig
  laut `phylum_equivalents.csv` bzw. `class_equivalents.csv`, FishBase als
  Chordata. Eine Klasse mit Platzhalter- oder ohne Stamm hat keine
  Stamm-Zeile, eine Platzhalter-Klasse keine Klassen-Zeile — dort ist
  nichts prüfbar, und die App sucht nicht. Die App prüft einen Suchtreffer
  über seine `ancestor_ids`: bei Arten den Stamm, bei Gattungen, Familien
  und Ordnungen auch die Klasse. Strenger als die Prüfung hier, die auch
  Ordnung oder Familie gelten lässt — die IDs dieser Ränge kennt die App
  für ein neues Taxon nicht.

`validate_mappings.sql` prüft beide Tabellen nach dem Import: Jede Klasse
mit Arten und echtem Stamm hat einen erlaubten Stamm (sonst fände die App
für ihre Arten nie eine ID; ein fehlendes Paar gehört in
`phylum_equivalents.csv`), jede Zeile nennt ein iNaturalist-Taxon des Rangs
und Namens, den sie behauptet, und keine abgelehnte Entität hat eine
Zuordnung oder ist keine Entität. Ältere Apps ignorieren die Tabellen.

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
  wieder auf, bekommt er seine alte ID zurück — auch wenn sie inzwischen ein
  Alias auf einen [Nachfolger](#nachfolger) ist.
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
`build.sh`), die nach den Quellen mit Entitäten und vor den ergänzenden
läuft. Die Quellen mit Entitäten schreiben **vorläufige IDs** mit Quelle
(`discere:fishbase_species:6509`); die Stage ersetzt sie in der ganzen
Referenz-DB durch die endgültigen:

- **Schlüssel bekannt** — die registrierte ID.
- **Art mit unbekanntem Schlüssel** — Abgleich gegen die Arten anderer
  Quellen, die in diesem Build schon eine Entität haben, je Quelle in der
  Reihenfolge ihrer `placement_priority`. Ein eindeutiger Treffer ist dieselbe
  Entität: Der Schlüssel kommt auf die bestehende ID, die Zeilen gehen
  zusammen (siehe [Einordnung](#einordnung)). Kein oder ein mehrdeutiger
  Treffer ergibt eine neue Entität, ein mehrdeutiger dazu einen Eintrag im
  Build-Bericht (Quelle `identity`).
- **Höheres Taxon mit bekanntem Schlüssel und anderem Namen** — Abbruch
  (`core/sql/identity_key_names.sql`). Höhere Taxa ordnet die Stage allein
  über den Schlüssel zu; trägt er einen anderen Namen als seine Entität im
  Vorgänger (ohne Leerzeichen am Rand und Groß- und Kleinschreibung), bekäme
  deren ID ein anderes Taxon, und Register, Aliase und Nutzerdaten zeigten
  auf etwas anderes. Ob es dasselbe Taxon in neuer Schreibweise ist, kann
  der Build nicht entscheiden. Arten sind ausgenommen: Ihr Name in `species`
  ist das Epitheton, dessen Schreibweise die Quellen unter gleichem
  Schlüssel korrigieren. Gleichnamige Taxa unterscheidet der Name nicht;
  bei Ordnungen und Familien bricht der Build deshalb auch ab, wenn sie
  unter dem Schlüssel einer anderen Klasse bzw. Ordnung hängen als im
  Vorgänger (Schlüssel der Quelle, nicht IDs). Fehlt die Elternstufe auf
  einer Seite, ist das kein Wechsel, ebenso wenig ein Elternschlüssel, den
  der Export für diese Familie in `source_parent_overrides` nennt (siehe
  [Stamm einer Familie gegen ihren Ordnungscode](#stamm-einer-familie-gegen-ihren-ordnungscode)).
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

Die ergänzenden Quellen schreiben danach direkt endgültige IDs. Am Ende des
Builds prüft `core/check_references.sh` jede Spalte, die auf eine Entität
verweist: keine vorläufige ID, keine ID ohne Entität, jeder Fremdschlüssel
löst auf.

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
- Die App schreibt alle Verweise von Alias-IDs auf die gültige ID um, bevor
  ein Dienst Nutzerdaten liest (siehe [Umschreiben in der
  App](#umschreiben-in-der-app)).
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

„Die vorhandene Zeile“ ist die, die schon unter der gültigen ID stand; gibt
es keine, bleibt die mit der kleinsten alten ID.

| Ablage | Spalte, Form | Bei Kollision |
|---|---|---|
| `flashcard_stats` | `species_id`, roh | eine Zeile bleibt, gewählt nach `last_review_date` absteigend (NULL zuletzt), dann `next_review_date` absteigend (NULL zuletzt), dann die Zeile mit der kleineren alten ID |
| `enrichment_species_work` | `species_id`, roh | die vorhandene Zeile bleibt, Consent-Flags ODER-verknüpft, `deck_count` neu aus `enrichment_species_deck_membership` gezählt |
| `enrichment_species_capability_state` | `species_id`, roh | eine Zeile bleibt: eine mit `state = 'done'`, wenn es eine gibt (ihr Ergebnis wandert mit den Cache-Tabellen), sonst die vorhandene; keine wird verworfen, denn fehlende Zeilen legt nur das Einplanen durch den Nutzer neu an |
| `enrichment_species_deck_membership` | `species_id`, roh | Duplikat verwerfen, die vorhandene Zeile bleibt |
| `enrichment_taxonomy_work_species` | `species_id`, roh | Duplikat verwerfen, die vorhandene Zeile bleibt |
| `inat_photo_cache` | `species_id`, roh | Duplikat verwerfen, die vorhandene Zeile bleibt |
| `species_photo_gap_ack` | `species_id`, roh | Duplikat verwerfen, die vorhandene Zeile bleibt |
| `external_identifier_cache` | `entity_id`, roh bei Arten (höhere Taxa: `rang:name`, nicht betroffen) | die vorhandene Zeile bleibt |
| `runtime_common_names` | `entity_key`, `species:<id>` bei Arten | kein Primärschlüssel; Duplikate sind Zeilen mit gleichem `entity_key`, `language_code`, `name` und `place_id` (NULL gleich NULL), davon bleibt die mit dem jüngsten `fetched_at` |
| `runtime_common_name_search_documents` | `entity_key`, `species:<id>` bei Arten; `entity_id`, roh bei **allen** Rängen (ein Gattungsdokument trägt die ID der Gattung) | Dokumente zu einem zusammenführen: die vorhandene Zeile bleibt mit ihrem wissenschaftlichen Namen, je Sprache kommen die Namen der anderen hinzu, die Suchtexte werden aneinandergehängt; der Volltextindex folgt |
| SharedPreferences `watchlist` | Liste von Art-IDs, roh | Duplikat verwerfen |

Die Matrix ist bei jeder neuen Ablage, die eine Referenz-ID speichert,
nachzuziehen, in der Nutzer-DB wie in den SharedPreferences; im Code steht
sie in `lib/shared/persistence/reference_id/reference_id_tables.dart`. Nicht
betroffen sind Tabellen, die über Namen oder Deck-IDs verweisen
(`enrichment_taxonomy_work` über `rang:name`, `enrichment_unresolved_names`,
`enrichment_jobs`, `decks`, `deck_config`), die Favoriten (Deck-IDs) und
die gespeicherten Bilder (Dateinamen aus der URL). Export, Teilen und
QR-Codes enthalten nur wissenschaftliche Namen (`CreateDeck.toJson`) und sind
von einem Alias nicht betroffen.

#### Umschreiben in der App

`ReferenceIdMigration` (`lib/shared/persistence/reference_id/`) wendet die
Aliase an. Der Bootstrap ruft sie bei jedem Start auf, sobald die
Referenz-DB bereitliegt — ob sie schon da war oder eben heruntergeladen
wurde — und bevor er einen Dienst baut:

- Sie liest die IDs, die die Nutzerdaten tragen (einige Hundert), schlägt
  nur diese in `entity_aliases` nach und legt die Treffer als temporäre
  Tabelle in die Nutzer-DB, gegen die alle Tabellen der Matrix umgeschrieben
  werden. Die Alias-Tabelle selbst (rund 185.000 Zeilen) wird weder kopiert
  noch angehängt.
- Alle Tabellen der Matrix werden in **einer** Transaktion umgeschrieben.
  Die Watchlist davor, weil SharedPreferences außerhalb der Transaktion
  liegen; das ist unbedenklich, weil das Umschreiben idempotent ist.
- Danach merkt sie sich die Version der Referenz-DB
  (`reference_id_aliases_applied_version` in den SharedPreferences). Stimmt
  die gemerkte Version mit der installierten überein, läuft nichts. Bricht
  der Lauf vorher ab — Absturz nach der Installation, Fehler in der
  Transaktion —, läuft er beim nächsten Start erneut; ein zweiter Lauf
  findet keine Alias-ID mehr und ändert nichts.
- Ein Fehler wird mit Stack ins Diagnose-Log geschrieben, die Transaktion
  zurückgerollt, und der Start geht weiter: Bis zum nächsten Versuch findet
  die App Lernstände unter abgelösten IDs nicht, verliert sie aber nicht.
- Das Log nennt je Tabelle die umgeschriebenen und verworfenen Zeilen;
  verworfene Zeilen schreibt es als Warnung auch ins Diagnose-Log.

Eine neue Referenz-DB wird deshalb nur im Bootstrap eingesetzt, nie unter
einer laufenden Sitzung. Ein Update, das während der Sitzung gefunden und
bestätigt wird, lädt im Hintergrund und wird geprüft neben die aktive Datei
gelegt (`<ref>.pending` mit Version und Schemaversion daneben), ohne Stempel.
Ein Hinweis bietet „Anwenden“ an: Das startet die App von innen neu, auf
demselben Weg wie ein Kaltstart — Dienste anhalten, Datenbanken schließen,
Bootstrap —, der die Datei einsetzt, stempelt und die Aliase anwendet. Ohne
„Anwenden“ geschieht dasselbe beim nächsten Start.

Eine ältere App, die keine Aliase anwenden kann, darf eine solche Referenz-DB
nicht installieren. Das sichert die Schemaversion: Ein Release mit Aliasen
trägt Schemaversion 2 und steht im Manifest nur unter `schemas["2"]`.
Ältere Apps lesen allein die oberste Ebene, und dort steht immer das neueste
Release mit Schemaversion 1; die App, die Aliase anwendet, nimmt das neueste
Release mit 1 oder 2 (siehe [Schritte](#schritte)).

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
Eine Art, für die der Build einen eindeutigen [Nachfolger](#nachfolger)
findet, wird stattdessen ein Alias auf ihn.
Das entscheidet die Identitäts-Stage, nicht jede Quelle für sich.

Weil jeder Build die DB neu anlegt, übernimmt die Identitäts-Stage solche
Entitäten aus dem Vorgänger: die Zeile selbst (Arten mit `status =
'deprecated'` und `deprecated_at`, das schon gesetzte bleibt), ihre
wissenschaftlichen Namen und Volksnamen, bei Arten auch ihre Bilder. Das gilt
für jeden Typ, auch für höhere Taxa, die keinen Status haben; so bleibt die
Elternkette jeder übernommenen Art vollständig, und die App kann Gattung und
Epitheton anzeigen.

Übernommen wird, was eine Karte zum Lernen braucht: Name, Einordnung (auch
für die Distraktoren im Multiple Choice) und Bilder. Ohne Bilder meldete die
App eine schon gelernte Karte als Fotolücke und böte an, sie aus dem Deck zu
entfernen. Bild-IDs tragen Quelle und Schlüssel der Art; dieselbe ID kann
im Build nur ein Bild ohne Art sein, dessen Art die Quelle nicht mehr
liefert, und weicht dem übernommenen. Merkmale und Verbreitung zeigt nur die
Detailseite, sie kommen nicht mit. Externe IDs auch nicht: Die
iNaturalist-Quelle schreibt ihre Zuordnungen bei jedem Build neu und nur für
aktive Arten; für eine veraltete Art sucht die App das Taxon bei iNaturalist
über den Namen.

Ein Teilbuild (`build.sh --plugin …`) liefert nur die Schlüssel seiner
Quellen; alle anderen Entitäten des Vorgängers sind darin übernommen und
deprecated, und die Nachfolger-Regel machte Arten der fehlenden Quellen zu
Aliasen. Ein Release entsteht deshalb nur aus einem vollständigen Build:
`build.sh` vermerkt in `metadata`, ob er alle Plugins ausgeführt hat, ohne
`--no-enrich`, `--initial` und `--accept-species-loss` und gegen das
veröffentlichte Release (nicht `--previous-release`), dazu Version und Prüfsumme dieses Vorgängers und ob
die Validierung bestanden ist. `publish_release.sh` prüft das mit
`core/check_publishable.sh` gegen das gerade veröffentlichte Manifest und
bricht sonst ab: Ein Build gegen ein älteres Release ließe die Aliase des
inzwischen veröffentlichten aus. Ebenso bricht es ab, wenn `--version` nicht
über der veröffentlichten Version liegt, denn die App lädt nur eine höhere.

### Einbruch einer Quelle

Liefert eine Quelle still nur einen Teil ihrer Arten — ein abgebrochener
Download, eine leere Tabelle im Parquet —, liegt der Build mit den übrigen
Quellen oft noch über den Mindestzahlen der Validierung. Die fehlenden Arten
würden übernommen und, wo ein Name passt, Alias auf eine Art einer anderen
Quelle; die App schriebe Lernstände dorthin um, und das lässt sich nicht
zurücknehmen. Die Identitäts-Stage zählt deshalb je Quelle, wie viele ihrer
im Vorgänger aktiven Arten-Schlüssel der Build nicht mehr liefert
(`core/sql/identity_source_loss.sql`), und bricht ab, wenn der Anteil über
der Schwelle liegt — auch, wenn die Quelle ganz fehlt. Die Zusammenfassung
im Log nennt den Anteil jeder Quelle.

Die Schwelle ist 5 %. Zwischen refdb-v2 (FishBase v26.07, SeaLifeBase
v26.04) und einem Build aus v25.04 fehlen 1,8 % der FishBase-Arten (652 von
36.763) und 0,1 % der SeaLifeBase-Arten (58 von 102.727) — mehr als ein Jahr
Datenstand rückwärts. Ein gewöhnliches Update bleibt darunter, ein Einbruch
liegt in aller Regel weit darüber.

Ein echter, größerer Rückgang ist eine Entscheidung, keine Ausnahme im Build:
Der Maintainer setzt im Manifest der Quelle `species_loss_limit_percent` auf
den geprüften Wert, begründet das im Commit, baut vollständig und
veröffentlicht; danach nimmt er die Schwelle wieder heraus.
`--accept-species-loss <quelle>` (`build.sh`, `core/identity.sh`) nimmt einen Rückgang dagegen nur
für diesen einen Lauf hin, zum Testen: Der Build gilt dann als unvollständig
und wird kein Release. Ein Teilbuild setzt es selbst für jede Quelle mit
Entitäten, die er nicht ausführt.

### Nachfolger

Weder FishBase noch SeaLifeBase führen ein Feld „ersetzt durch“. Nimmt eine
Quelle Art A in Art B auf oder benennt sie unter neuem Schlüssel um, führt
sie A's Namen danach als Synonym unter B — oder als gültigen Namen der Art
mit dem neuen Schlüssel. Daraus leitet die Identitäts-Stage einen Nachfolger
ab (`core/sql/identity_successor.sql`, nach der Vergabe der IDs und vor der
Übernahme):

- Eine **Art** des Vorgängers ohne aktiven Schlüssel bekommt einen
  Nachfolger, wenn ihr gültiger Name im Vorgänger (Gattung + Epitheton,
  normalisiert wie im [Abgleich](#abgleich)) in diesem Build ein Name —
  gültig oder Synonym, nicht `misapplied name` — **genau einer** aktiven Art
  ist. Das gilt auch für eine Art, die schon im Vorgänger deprecated war.
- Ihre ID wird ein **Alias** auf den Nachfolger, und die Aliase des
  Vorgängers, die auf sie zeigten, werden auf ihn nachgeführt. Die App
  überträgt damit Karten, Lernstand und Watchlist beim Start (siehe
  [Umschreiben in der App](#umschreiben-in-der-app)). Die Art selbst wird
  nicht übernommen, ihre Namen auch nicht.
- Ihre **Schlüssel** bleiben im Register inaktiv auf ihrer bisherigen ID, die
  nun ein Alias ist. Ein inaktiver Schlüssel zeigt deshalb auf eine Entität
  oder auf einen Alias, dessen Ziel eine Entität seines Typs ist. Beim
  einmaligen Ableiten des Registers ist die bisherige ID die abgeleitete;
  sie wird ebenso Alias wie die alte ID mit Quelle.
- **Mehrere Kandidaten**: keine Wahl. Die Art wird übernommen und deprecated
  wie ohne Kandidat, der Build-Bericht nennt sie mit allen Kandidaten
  (Kategorie `successor_ambiguous`). Jeder Nachfolger steht dort ebenfalls
  (`successor`), damit eine Zuordnung über ein falsches Synonym auffällt.
- Kandidaten sind die Arten dieses Builds mit den Namen aller Quellen, die
  sie liefern: Geht der Nachfolger hier aus zwei Quellen hervor, zählen die
  Namen beider. Übernommene Arten sind keine Kandidaten; eine Kette
  entsteht so nicht.
- **Nur der gültige Name** der alten Art ist Brücke, nicht ihre bisherigen
  Synonyme. Ein Synonym der alten Art, das hier Synonym einer anderen ist,
  belegt nur, dass beide Quellen denselben alten Namen irgendwo einordnen;
  am Build gegen refdb-v2 hätte diese Erweiterung 14 Arten zugeordnet, vier
  davon dem FishBase-Platzhalter *Genus Species* (siehe
  [Platzhalter der Quellen](#platzhalter-der-quellen)).
- **Höhere Taxa** bekommen nie einen Nachfolger: Gleichnamige Gattungen
  verschiedener Quellen sind oft Homonyme.

**Der Schlüssel kehrt zurück.** Liefert eine Quelle den Schlüssel einer
ersetzten Art wieder, bekommt er seine bisherige ID zurück, und die Art ist
wieder eine eigene Entität neben ihrem Nachfolger — der Build legt keine zwei
aktiven Arten still zusammen. Der Alias auf den Nachfolger entfällt, der
Build-Bericht nennt ihn (`successor_withdrawn`). Nutzerdaten, die der Alias
schon auf den Nachfolger umgeschrieben hat, bleiben dort: Ein Alias wirkt
nur vorwärts. Ein Alias des Vorgängers, dessen ID im Vorgänger zugleich
Entität war, ist kein solcher Fall; er bricht den Build weiter ab.

Die Zusammenfassung im Log nennt die Zahl der Nachfolger, der mehrdeutigen
und der zurückgenommenen Aliase.

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
| Quelle als Plugin mit Manifest und `sources`-Eintrag | ja, für FishBase, SeaLifeBase, die kuratierten Ergänzungen (`curated`) und die iNaturalist-Zuordnung (`inaturalist`) |
| Beiträge mit `source` | ja (`common_names`, `pictures`, `taxonomy_traits`, …) |
| Weiches Löschen von Arten | ja — die Identitäts-Stage übernimmt Entitäten ohne aktiven Schlüssel aus dem Vorgänger, Arten als `deprecated` |
| Nachfolger für Arten ohne aktiven Schlüssel | ja — über den gültigen Namen, eindeutig unter den Namen aktiver Arten; die alte ID wird Alias (`core/sql/identity_successor.sql`) |
| `depends_on_sources` und Sortierung | ja — `core/plugin_order.sh`, in zwei Gruppen (Quellen mit Entitäten, Identitäts-Stage, ergänzende Quellen); `--plugin` nimmt Abhängigkeiten mit |
| `placement_priority` | ja — FishBase 10, SeaLifeBase 20; entscheidet, welche Zeile gilt, wenn zwei Quellen dieselbe Art liefern. Pflicht für jede Quelle, die Entitäten liefert |
| Release nur aus vollständigem Build | ja — Build-Vermerk in `metadata` (`build.sh`), geprüft von `publish_release.sh` über `core/check_publishable.sh`, samt Abgleich des Vorgängers mit dem veröffentlichten Manifest |
| Platzhalter der Quellen ausgeschlossen | ja — FishBase FamCode 0, GenCode 0 samt Arten und Beiträgen, SeaLifeBase *DummyGenus DummySpecies*; Rang-Platzhalter von SeaLifeBase („Not assigned“, „Incertae sedis (…)“) bleiben und sind markiert (`is_placeholder`, `core/placeholders.sh`; siehe [Bekannte Grenzen](#bekannte-grenzen)) |
| Abgleich in `core/` | ja — `core/match.sh`/`core/sql/match.sql`, über Namen samt Synonymen; genutzt von `inaturalist` und von der Identitäts-Stage für Arten mit unbekanntem Schlüssel |
| Build-Bericht | ja — `<db>.build-report/`, eine TSV je Quelle |
| IDs ohne Quelle, Register (`entity_source_keys`) | ja — Identitäts-Stage (`core/identity.sh`); Quellen mit Entitäten schreiben vorläufige IDs mit Quelle, ergänzende Quellen laufen danach, das Release trägt nur `discere:<typ>:<nr>`. `schema.sql` lässt beide Formen zu (`GLOB 'discere:*:*'`), die Validierung nur die endgültige |
| Aliase | ja — ETL (`entity_aliases`, jede abgelöste ID auf ihre gültige) und App (`ReferenceIdMigration` beim Start, Schemaversion 2; Updates aus der Sitzung werden bereitgelegt und beim Start eingesetzt) |
| `optional` im Manifest | ja — `--no-enrich` überspringt optionale Quellen samt Abhängigen (heute `inaturalist`), außerdem Stage 01b |
| iNaturalist-Zuordnung | ja — Quelle `inaturalist` mit `sources`-Eintrag; schreibt `entity_external_ids`, bei höheren Taxa unter Namensschlüsseln (`genus:barbus`), die die App abfragt. Mehrere gleichnamige Zeilen einer Rangtabelle teilen diesen Schlüssel; zugeordnet wird nur, wenn das iNaturalist-Taxon zur Kette jeder passt (siehe [Stamm und Kette bei der iNaturalist-Zuordnung](#stamm-und-kette-bei-der-inaturalist-zuordnung)) |

---

## Umsetzung

### Übergang: nur Beiträge

Bis das erste Release mit Schemaversion 2 veröffentlicht ist (Schritt 4),
dürfen weitere Quellen **nur Beiträge zu vorhandenen Entitäten** liefern und
keine Entitäten anlegen. Fehlt eine
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
3. *(umgesetzt)* **Register und Aliase** — Register, Aliase und
   Lebenszyklus in der Identitäts-Stage; die App schreibt ihre Verweise beim
   Start um und akzeptiert Schemaversion 2 (siehe [Umschreiben in der
   App](#umschreiben-in-der-app)).
4. *(im ETL umgesetzt)* **Umstellung aller IDs** auf das Format ohne Quelle:
   Der erste Build gegen ein Release ohne Register leitet es ab, und jede
   bisherige ID wird ein Alias auf ihre neue. Das Release erprobt den
   Alias-Mechanismus einmal vollständig, bevor er für einzelne Doppel gebraucht
   wird.
5. **Danach** dürfen Quellen Entitäten anlegen.

Ein Release nach diesem Stand trägt Schemaversion 2. `publish_release.sh`
leitet sie aus der DB ab (`core/schema_version.sh`: IDs ohne Quelle mit
Register und Aliasen sind 2, IDs mit Quelle ohne Register 1, alles andere
bricht ab) und nimmt keine Angabe von Hand an.

Das Manifest nennt unter `schemas` je Schemaversion deren neuestes Release,
mit der Schemaversion als Schlüssel; seine oberste Ebene ist immer das
neueste Release mit Schemaversion 1, für Apps, die `schemas` nicht kennen
(Format in [`FLUTTER_INTEGRATION.md`](../FLUTTER_INTEGRATION.md#update-mechanismus--publishing)).
Jede App bekommt das neueste Release, das sie lesen kann: Ältere Apps
bleiben beim Release mit Schemaversion 1, statt mit unbekannten IDs ihre
Lernstände zu verlieren, auch nach einer Neuinstallation; die App, die
Aliase anwendet, nimmt unter den Releases mit 1 oder 2 das mit der höchsten
`version`. Wann eine App mit einem neuen Schema ausgeliefert wird und wann
das erste Release damit erscheint, spielt deshalb keine Rolle.

Vorgänger eines Builds ist das neueste Release über alle Schemaversionen
(`core/manifest_newest.sh`), nicht die oberste Ebene: Die nennt nach einem
Release mit Schemaversion 2 weiter das ältere mit 1, und ein Build dagegen
ließe die Aliase des neueren aus. Die Auswahl folgt derselben Regel wie die
App: Mit `schemas` zählen nur dessen Einträge, ohne `schemas` allein die
oberste Ebene. Ein Vorgänger ist so immer ein Release, das eine App auch
installiert.

### Bekannte Grenzen

- **Höhere Taxa werden quellenübergreifend nicht zusammengeführt.**
  Gleichnamige Gattungen, Familien, Ordnungen und Klassen zweier Quellen
  bleiben eigene Entitäten. Der Name allein trennt Homonyme nicht: Zwischen
  FishBase und SeaLifeBase gibt es 97 gleichnamige Gattungen und eine
  gleichnamige Familie (*Chilodontidae*), und keine davon gehört zur selben
  Familie oder Klasse (*Acanthus* ist bei FishBase ein Doktorfisch, bei
  SeaLifeBase eine Pflanze). Eine Regel dafür braucht mehr als den Namen,
  etwa die Elternkette oder eine gemeinsame externe ID.
- **Rang-Platzhalter bleiben Entitäten.** SeaLifeBase führt Klassen,
  Ordnungen und Familien namens „Not assigned“ oder „Incertae sedis (…)“
  (v26.06: 31 Klassen, 64 Ordnungen, 102 Familien). Sie halten echte Arten in
  ihrer Kette und werden deshalb importiert. Stage 02d markiert sie nach
  ihrem Namen (`is_placeholder`, Regel in `core/sql/placeholders.sql`) und
  listet jeden im Build-Bericht; die App zeigt sie als „nicht zugeordnet“,
  bietet sie nicht als Distraktor an und findet sie nicht in der Suche. Jede
  Platzhalterstufe bleibt eine eigene Entität unter ihrer Elternstufe. Eine
  Art mit Platzhalter-Familie bekommt im Familienmodus keine Karte, denn sie
  hat dort keine Antwort.
  Markiert ist nur, was die Namensregel trifft: Die FishBase-Ordnungen
  „…/misc“ (etwa „Eupercaria/misc“) sammeln ebenfalls Familien ohne eigene
  Ordnung, tragen das Flag aber nicht.
  FishBase führt außerdem die Platzhalter-Familie FamCode 0 „Family“. Der
  Export schließt sie aus; in der DB steht sie trotzdem, aus dem Vorgänger
  übernommen, weil die veraltete Gattung „To“ mit zwei veralteten Arten
  darunter hängt. Ohne aktive Art erscheint sie in keiner Liste und keiner
  Suche.
- **Die Kette kann über der Gattung abbrechen.** In SeaLifeBase v26.06 zeigen
  zwei Gattungen (*Abrina*, *Ophiolophus*) auf einen FamCode, den die Quelle
  nicht führt, und zwei Familien haben keine Ordnung: *Lernaeodiscidae* zeigt
  auf einen unbekannten Ordnungscode, *Mictocarididae* nennt nur den Namen
  einer Ordnung, die die Quelle nicht führt. Über einen Namen auflösen lässt
  sich keine dieser Stufen; die Stufen bleiben leer. Die Arten der beiden
  Gattungen und von *Lernaeodiscidae* nennen selbst eine andere Familie und
  hängen deshalb an keiner Gattung (siehe
  [Gattung und Familie einer Art widersprechen sich](#gattung-und-familie-einer-art-widersprechen-sich));
  unter *Mictocarididae* bleibt eine aktive Art. Dazu kommen fünf Familien,
  deren Ordnungscode in einen anderen Stamm zeigt und deren eigene Angaben
  keine Ordnung finden, und *Ectocotylidae* aus der Ausnahmeliste (siehe
  [Stamm einer Familie gegen ihren Ordnungscode](#stamm-einer-familie-gegen-ihren-ordnungscode)).
  Die App lädt solche Arten
  trotzdem und zeigt die fehlenden Stufen als „nicht zugeordnet“; im
  Gattungs- bzw. Familienmodus bekommen sie ohne Antwort keine Karte.
- **Die SeaLifeBase-Einordnung ist teils veraltet.** Weichen Gattung und
  FamCode einer Art nur in Familie oder Ordnung ab, bleibt die Gattung (siehe
  [Gattung und Familie einer Art widersprechen sich](#gattung-und-familie-einer-art-widersprechen-sich)).
  Eine Stichprobe gegen WoRMS fand darunter etwa so viele veraltete wie
  aktuelle Familien der Gattung. Entscheiden ließe sich das nur mit einer
  Referenz von außen ([#337](https://github.com/discere-app/discere/issues/337)).
- **Doppelte Codes lösen sich nur über die Angaben der Quelle auf.** Unter
  einem doppelten Ordnum entscheiden Ordnungsname und ClassNum, die die
  Familie selbst nennt, und welche Zeile Arten hält (siehe
  [Doppelte Codes in der Quelle](#doppelte-codes-in-der-quelle)). Eine
  Familie, deren ClassNum veraltet ist — bei eindeutigem Ordnum weicht sie
  in v26.06 bei 329 Familien von der Klasse ihrer Ordnung ab —, bliebe unter
  einem doppelten Ordnum ohne Ordnung. Eine Invariante über die eigene
  Klasse der Familie gibt es deshalb weder im Export noch in
  `validate.sql`: Die DB kennt diese Angabe nicht, und über alle Familien
  gälte sie nicht. Die Regel prüfen Bericht und Tests.
- **Der Stamm einer Familie prüft nur, was die Quelle selbst nennt.** Ein
  Ordnungscode, der in eine falsche Klasse desselben Stamms zeigt, fällt
  nicht auf: Die eigene ClassNum der Familie ist dafür zu oft veraltet oder
  falsch (siehe
  [Stamm einer Familie gegen ihren Ordnungscode](#stamm-einer-familie-gegen-ihren-ordnungscode)).
  Ebenso wenig eine Familie, deren eigener Stamm mit dem falschen Code
  übereinstimmt, oder ein Paar der Liste gleichwertiger Stämme, unter dem
  eine Familie tatsächlich falsch hängt (eine echte Plattwurm-Familie unter
  einer Ordnung der Xenacoelomorpha bestünde die Prüfung). Solche Fälle
  fängt nur die kuratierte Ausnahmeliste, und nur die, die jemand gefunden
  hat.
- **Ein neuer Name oder Elternschlüssel unter bekanntem Schlüssel stoppt
  den Build.** Die Identitäts-Stage erkennt einen Schlüsselwechsel am Namen
  und, bei Ordnungen und Familien, am Elternschlüssel (siehe
  [Das Register vergibt IDs stabil](#das-register-vergibt-ids-stabil)).
  Korrigiert eine Quelle die Schreibweise eines höheren Taxons oder stellt
  sie eine Familie in eine andere Ordnung, unter gleichem Code, bricht der
  Build ebenso ab, und es braucht eine Entscheidung im Code; zwischen
  refdb-v2 und v26.06 kommt beides nicht vor. Eine solche Entscheidung ist
  die Regel zum Stamm einer Familie: Die Familien, die sie umhängt, stehen
  in `source_parent_overrides`. Ein Wechsel zwischen zwei
  gleichnamigen Gattungen derselben Familie fiele nicht auf.
- **Arten, die schon getrennte Entitäten sind, werden nicht zusammengeführt.**
  Der Abgleich läuft nur für Arten mit unbekanntem Schlüssel. Zwei Einträge,
  die sich erst später als dieselbe Art erweisen, bleiben getrennt, bis ein
  eigener Schritt eine davon zum Alias macht.

- **Die Prüfung der iNaturalist-Zuordnung ist nur so gut wie die eigene
  Kette.** Steht eine Art bei SeaLifeBase im falschen Stamm (das Seegras
  *Halophila* unter den Moostierchen, Ciliaten unter „Not Assigned
  (Plantae)“), lehnt sie die richtige Zuordnung ab; eine Art ohne Gattung oder eine gleichnamige Zeile
  mit Art, aber ohne Kette verhindert sie ganz. Nach einer Umstellung der Familie fallen
  auch richtige Synonym-Treffer weg. Umgekehrt trennt sie kein Homonym in
  derselben Klasse, solange der Artname bei iNaturalist nur ein Taxon trägt
  (bei Gattungen: solange Klasse, Ordnung oder Familie gleich sind); dort
  hilft erst eine gemeinsame externe ID. Ein Synonym mit gleichem
  Epitheton, das in WoRMS eine andere Art ist (*Scissurella tabulata* →
  *Satondella tabulata*, *Trichotropis insignis* → *Torellia insignis*,
  *Volvarina hennequini* → *Dentimargo hennequini*), geht durch. Und die
  Prüfung vertraut der Einordnung bei iNaturalist: Hängt iNaturalist ein
  Taxon falsch ein (den Fangschreckenkrebs *Miyakea nepa* unter eine
  Mottengattung), zeigt die Kette dort etwas anderes, als das Taxon ist.
  Die App sucht ein Taxon, für das
  die Referenz-DB keine ID hat, zur Laufzeit selbst über den Namen und kann
  dabei das abgelehnte Taxon wieder finden.

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
